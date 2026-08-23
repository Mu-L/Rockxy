import Darwin
import Foundation
import os

// Config-only file codec for the portable `.rockxyproject` document. This layer
// only encodes/decodes and validates bytes: it never presents UI, mutates the
// live ``ProjectStore``, or orchestrates import/merge. Reads fail closed on a
// symlink, non-regular node, oversized data, corrupt JSON, an unsupported format
// version, or any structurally invalid document — mirroring the fail-closed and
// atomic-write posture of ``ProjectCatalogRepository``.

// MARK: - PortableProjectDocumentError

enum PortableProjectDocumentError: Error, Equatable {
    case fileMissing
    case symbolicLink
    case notRegularFile
    case fileTooLarge(bytes: Int)
    case encodedDocumentTooLarge(bytes: Int)
    case corruptData
    case unsupportedFormatVersion(found: Int)
    case invalid(PortableProjectError)
}

// MARK: - PortableProjectDocument

enum PortableProjectDocument {
    // MARK: Internal

    /// Proposed public file extension for a portable Project configuration.
    static let fileExtension = "rockxyproject"

    /// Maximum encoded/pre-read document size (1 MiB). A config-only document never
    /// carries traffic, so this bounds both hostile input and accidental bloat.
    static let maxDocumentByteSize = Int(ImportSizePolicy.maxProjectConfigFileSize)

    /// Encodes a ``Project``'s portable, allowlisted configuration to JSON bytes.
    static func encode(_ project: Project) throws -> Data {
        try encode(PortableProject(exporting: project))
    }

    /// Encodes an already-built portable document to JSON bytes, enforcing the size cap.
    static func encode(_ portable: PortableProject) throws -> Data {
        let data = try encoder.encode(portable)
        guard data.count <= maxDocumentByteSize else {
            throw PortableProjectDocumentError.encodedDocumentTooLarge(bytes: data.count)
        }
        return data
    }

    /// Atomically writes a Project's portable configuration to `url`. The sibling
    /// temporary file is created as `0600` before any content is written, then
    /// renamed over the destination so a symlink is replaced rather than followed.
    static func write(
        _ project: Project,
        to url: URL,
        fileManager: FileManager = .default,
        beforePublishing: ((URL) throws -> Void)? = nil
    )
        throws
    {
        let data = try encode(project)
        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).rockxyproject.tmp")
        var descriptor: Int32? = try openForPrivateWrite(temporaryURL)
        guard let openDescriptor = descriptor else {
            throw POSIXError(.EIO)
        }
        var didPublish = false
        defer {
            if let descriptor {
                Darwin.close(descriptor)
            }
            if !didPublish {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try writeAll(data, to: openDescriptor)
        guard Darwin.fsync(openDescriptor) == 0 else {
            throw currentPOSIXError()
        }
        guard Darwin.close(openDescriptor) == 0 else {
            descriptor = nil
            throw currentPOSIXError()
        }
        descriptor = nil

        try beforePublishing?(temporaryURL)
        guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
            throw currentPOSIXError()
        }
        didPublish = true
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        Self.logger.info("Exported portable project configuration")
    }

    /// Reads and fully validates a portable document from `url`, returning the
    /// decoded DTO only after every fail-closed check passes. Never follows a
    /// symlink and never reads a non-regular or oversized node.
    static func read(
        from url: URL,
        fileManager _: FileManager = .default,
        afterOpening: (() throws -> Void)? = nil
    )
        throws -> PortableProject
    {
        let data = try readBoundedRegularFile(from: url, afterOpening: afterOpening)

        let portable: PortableProject
        do {
            portable = try decoder.decode(PortableProject.self, from: data)
        } catch {
            throw PortableProjectDocumentError.corruptData
        }

        guard portable.formatVersion == PortableProject.currentFormatVersion else {
            throw PortableProjectDocumentError.unsupportedFormatVersion(found: portable.formatVersion)
        }
        do {
            try portable.validate()
        } catch let error as PortableProjectError {
            throw PortableProjectDocumentError.invalid(error)
        }
        return portable
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "PortableProjectDocument"
    )

    private static let encoder: JSONEncoder = {
        let configured = JSONEncoder()
        configured.outputFormatting = [.sortedKeys]
        return configured
    }()

    private static let decoder = JSONDecoder()

    private static func openForPrivateWrite(_ url: URL) throws -> Int32 {
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw currentPOSIXError()
        }
        return descriptor
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0, errno == EINTR {
                    continue
                }
                guard written > 0 else {
                    throw currentPOSIXError()
                }
                offset += written
            }
        }
    }

    /// Opens once with no-follow semantics, validates that descriptor, and bounds
    /// the read itself. The optional hook is a deterministic regression-test seam
    /// for replacing the pathname after the descriptor is already secured.
    private static func readBoundedRegularFile(
        from url: URL,
        afterOpening: (() throws -> Void)?
    )
        throws -> Data
    {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT:
                throw PortableProjectDocumentError.fileMissing
            case ELOOP:
                throw PortableProjectDocumentError.symbolicLink
            default:
                throw currentPOSIXError()
            }
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw currentPOSIXError()
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw PortableProjectDocumentError.notRegularFile
        }
        guard metadata.st_size >= 0,
              metadata.st_size <= off_t(maxDocumentByteSize) else
        {
            throw PortableProjectDocumentError.fileTooLarge(bytes: Int(metadata.st_size))
        }

        try afterOpening?()
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: maxDocumentByteSize + 1) ?? Data()
        guard data.count <= maxDocumentByteSize else {
            throw PortableProjectDocumentError.fileTooLarge(bytes: data.count)
        }
        return data
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
