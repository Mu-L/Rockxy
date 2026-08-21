<div dir="rtl">

<p align="center">
  <img src="docs/logo/logo.png" alt="Rockxy" width="128" />
</p>

<h1 align="center">Rockxy</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.vi.md">Tiếng Việt</a> |
  <a href="README.zh.md">中文</a> |
  <a href="README.zh-TW.md">繁體中文</a> |
  <a href="README.es.md">Español</a> |
  <a href="README.pt-BR.md">Português do Brasil</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.fr.md">Français</a> |
  <a href="README.de.md">Deutsch</a> |
  <a href="README.it.md">Italiano</a> |
  <a href="README.tr.md">Türkçe</a> |
  <a href="README.pl.md">Polski</a> |
  <a href="README.nl.md">Nederlands</a> |
  <a href="README.ru.md">Русский</a> |
  <a href="README.uk.md">Українська</a> |
  <a href="README.ar.md">العربية</a> |
  <a href="README.fa.md">فارسی</a> |
  <a href="README.bn.md">বাংলা</a> |
  <a href="README.ro.md">Română</a> |
  <a href="README.ka.md">ქართული</a>
</p>

<p align="center">
  <strong>وكيل تصحيح الأخطاء مفتوح المصدر وقابل للتدقيق لنظام التشغيل macOS.</strong>
</p>

<p align="center">
  يمكنك اعتراض حركة مرور HTTP/HTTPS/WebSocket/GraphQL وفحصها وتعديلها باستخدام تطبيق Swift أصلي يمكنك فحصه وإنشاؤه والوثوق به.<br>
  تم تصميمه لسير عمل تصحيح الأخطاء في عصر API والهواتف المحمولة وMCP والذكاء الاصطناعي وعصر blockchain مع تطور Rockxy.<br>
  بديل local-first بترخيص AGPL-3.0 لـ <a href="#rockxy-مقابل-البدائل">Proxyman و Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy running on macOS" width="800" />
  </a>
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.35.0** — 2026-08-19

### Added

- Follow Live keeps each workspace on the newest request that matches its active filters until you navigate traffic manually.
- Focus actions are now explicit sidebar buttons, making focused traffic views easier to discover and control.

### Fixed

- Stabilized live request-table refresh and selection while high-volume captures and app metadata updates arrive.
- Kept HTTPS decryption controls accessible with clearer host and app scope, retry guidance after TLS rejection, and safer encrypted passthrough recovery.
- Preserved helper reset and reinstall recovery across development rebuilds, and now prompts for a clean reopen after app replacement.
- Rebalanced sidebar, Context Dock, and inspector sizing while preserving each workspace's active context and manual divider choices.

### Changed

- Workspace feedback now appears in the relevant pane without obscuring capture controls or unrelated workspaces.
- Official builds now include clearer binary licensing, public-source boundaries, third-party notices, and release provenance.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## أبرز الفروع الحالية

- يحقق AI Assistant الآن في طلب واحد أو أكثر من الطلبات المحددة باستخدام تحليل محلي مدمج أو نموذج Ollama/provider مُعد اختياريًا، مع تأكيد Review Data صريح، وتنقيح محدود، واستجابات بث، وكشف الأدلة، وعمليات handoff يبدأها المستخدم.
- يتضمن الشريط الجانبي الأصلي الآن Focus Sets قابلة لإعادة الاستخدام لنطاقات app/domain/path بالإضافة إلى Noise Control على مستوى مساحة العمل يخفي النطاقات أو المسارات المطابقة دون إيقاف الالتقاط.
- تستخدم مساحة العمل الرئيسية الآن split views أصلية عمودية وأفقية لـ Context Dock والمفتش السفلي، مع الحفاظ على فواصل بكامل الارتفاع، وفواصل toolbar/footer منسقة، وإعادة تحجيم تلقائية للتخطيط.
- يشتمل Upstream Proxy الآن على تكوين الوكيل التلقائي المجاني/الأساسي مع توجيه عنوان URL لـ PAC `DIRECT` وHTTP وHTTPS مع الحفاظ على SOCKS5 وحدود سياسة المصادقة الحالية.
- تغطي مسارات عمل التصدير الآن OpenAPI YAML/HTML ونشر Gist لحركة المرور المحددة مع إنشاء حمولة قابلة للتنقيح.
- تتضمن أدوات المفتش الآن تصفية JSONPath/المفتاح/القيمة ومعاينات سريعة لنص الحمولة النافعة المحدد مثل JWTs.
- يضيف فحص حركة AI وWeb3 الآن تسميات البروتوكول وعلامات تبويب المفتش وملخصات التصحيح لاستدعاءات النماذج المعترف بها وحركة JSON-RPC وتلميحات الدفع بأسلوب x402.
- يعكس إعداد مطور Node.js الآن العميل المحدد أثناء التحقق من الصحة ويحتوي على نموذج دليل أكمل للمضيف المحلي.
- يغطي Developer Setup Hub الآن أوقات التشغيل والمتصفحات والعملاء والأجهزة والأطر والبيئات باستخدام مقتطفات خاصة بالهدف ومراقبي التحقق من الصحة ومحتوى الدليل الصادق.
- يتضمن فحص WebSocket binary-frame الآن heuristic محدودة وعند الطلب لتنسيق Protobuf wire-format دون إضافة decoder work إلى capture hot path.
- تركز خارطة الطريق العامة الآن على قواعد أعمق مدركة للبروتوكول وإعادة التشغيل والمقارنة ومشاركة أدلة منقحة أكثر أمانًا.

## الميزات

الأدوات التي تستخدمها عندما لا تكون أدوات تطوير المتصفح كافية. يعمل تصحيح أخطاء حركة المرور الأساسية لنظامي التشغيل Mac وiOS، وهو موجود في نظام التشغيل macOS، مع الإصدارات العامة وسير العمل المحلي أولاً.

### التقاط حركة المرور

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

افحص حركة مرور HTTP، وHTTPS، وWebSocket، وGraphQL من أي تطبيق Mac، أو CLI، أو جهاز iOS. تنتهي أدوات تطوير المتصفح عند المتصفح — يرى Rockxy بقية مجموعتك.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### تصفية وبحث متقدم

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

تضييق نطاق آلاف الطلبات التي تم التقاطها في ثوانٍ. اجمع بين عوامل تصفية الطريقة والمضيف والحالة والرأس والنص والعملية - أو قم بإجراء بحث عن النص الكامل عبر الجلسة بأكملها.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets وNoise Control

حوّل التحقيقات المتكررة إلى نطاقات قابلة لإعادة الاستخدام في الشريط الجانبي. تجمع Focus Sets بين تضمينات التطبيق والنطاق والمسار واستبعادات النطاق/المسار، وتستمر بين عمليات التشغيل، وتتوفر في كل مساحة عمل. يستمر Noise Control في التقاط القياس عن بعد وحركة المرور منخفضة القيمة، لكنه يخفيها من مساحة العمل الحالية.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="يشرح Rockxy AI Assistant حركة المرور المحددة بجوار جدول الطلبات والشريط الجانبي الأصليين" width="820" />

حدد طلبًا واحدًا أو أكثر من الطلبات الملتقطة واسأل عما حدث أو فشل أو تغير أو ما يجب التحقق منه بعد ذلك. يبدأ Rockxy بتحليل يستند إلى الأدلة على هذا الـ Mac؛ ولا يعمل نموذج Ollama أو provider المُعد إلا بعد أن يعرض Review Data السياق الدقيق والمحدود والمنقح. يمكن للردود كشف طلب المصدر وإعداد مهام متابعة أصلية، لكنها لا تعدّل حركة المرور أو تنفذ الإجراءات تلقائيًا.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[اقرأ دليل AI Assistant](docs/features/ai-assistant.mdx).

### خادم MCP لعملاء الذكاء الاصطناعي الخارجيين

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

اسمح لـ Claude Desktop أو Cursor بفحص حركة المرور التي تم التقاطها عبر عشر أدوات للقراءة فقط في خادم MCP المحلي لـ Rockxy. اسأل "لماذا فعل هذا 500؟" بدلاً من لصق الرؤوس في الدردشة. التنفيذ مفتوح المصدر، ومصادق عليه بالرمز المميز، ويحافظ على تنقيح البيانات الحساسة مفعّلًا افتراضيًا.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### مركز إعداد المطور

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

انسخ ولصق مقتطفات الوكيل لـ Python وNode.js وGo وRust وcURL وDocker والمتصفحات، ثم انقر فوق "تشغيل اختبار" للتأكد من تدفق حركة المرور فعليًا.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### إدارة الشهادات لتصحيح أخطاء HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

تم إنشاء CA الجذر P-256 ECDSA عند الإطلاق لأول مرة، ومختومًا في سلسلة المفاتيح الخاصة بك. فك تشفير HTTPS من المحاولة الأولى؛ تمر المضيفات المثبتة تلقائيًا.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### وكيل SSL وفك تشفير HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

اختر المضيفين الذين سيحصلون على فك تشفير TLS. تعرض حركة المرور التي تم فك تشفيرها الرؤوس الحقيقية وJSON؛ كل شيء آخر يمر عبر مشفرة. تتيح لك قواعد Wildcard النطاق حسب المجال بنقرة واحدة.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### تجاوز الوكيل

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

تخطي مضيفين محددين حتى لا تدخل التطبيقات المثبتة بالشهادة أو الخدمات الداخلية أو القياس عن بعد المزعج أبدًا في الالتقاط. تحافظ أحرف البدل على القائمة قصيرة ويركز سجل طلباتك على ما يهمك بالفعل.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### قائمة الحظر

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

جعل أي مضيف يفشل. أسقط شبكات الإعلانات، أو أدوات التتبع التابعة لجهات خارجية، أو التبعية غير المستقرة لترى كيف يتدهور تطبيقك عند اختفائه - دون تغيير سطر من التعليمات البرمجية.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### الخريطة المحلية

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

قم بتقديم ملف محفوظ أو شجرة دليل بدلاً من الاستجابة المباشرة. قم بتبديل حمولة JSON أو إعادة تشغيل لقطة أو تثبيت واجهة برمجة التطبيقات غير المستقرة التابعة لجهة خارجية على نسخة محلية أثناء تصحيح الأخطاء.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### خريطة عن بعد

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

أعد كتابة وجهة الطلب الذي تم التقاطه دون لمس رمز التطبيق أو /etc/hosts. قم بتوجيه حركة الإنتاج إلى التدريج، أو خادم التطوير الخاص بك، أو جهاز زميل للحصول على نسخة مكررة من الأخطاء.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### نقاط التوقف والقواعد

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

قم بإيقاف طلب أو استجابة مؤقتًا، أو تحرير الطريقة، أو الرؤوس، أو النص، أو الحالة، ثم تابع. أسرع طريقة لاختبار "ماذا لو قامت واجهة برمجة التطبيقات بإرجاع 401؟" دون لمس الخلفية.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### تعديل الرؤوس

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

قم بإضافة أو إزالة أو استبدال الرؤوس على أي مضيف دون إعادة النشر. اختبر تغييرات CORS أو المصادقة أو ذاكرة التخزين المؤقت في ثوانٍ باستخدام الإعدادات المسبقة المضمنة.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### رؤوس الطلبات والاستجابة المخصصة

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

قم بترقية أي رأس طلب أو استجابة إلى عمود من الدرجة الأولى في جدول حركة المرور. أبقِ مصادر الطلب والاستجابة منفصلة، واحفظ الرؤوس التي تهمك، ثم تصفح request IDs وtrace IDs وحالة ذاكرة التخزين المؤقت أو البيانات الوصفية المخصصة دون فتح كل مفتش.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### ظروف الشبكة

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

يمكنك التبديل إلى شبكات 3G أو EDGE أو LTE أو WiFi أو تأخير مخصص. الكمبيوتر المحمول الخاص بك متصل بالألياف. المستخدمون لديك ليسوا كذلك - شاهد تجربة المستخدم عند 400 مللي ثانية RTT قبل أن يفعلوا ذلك.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### يؤلف - تحرير وإعادة التشغيل

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

أعد بناء أي طلب HTTP تم التقاطه - قم بتغيير الطريقة أو عنوان URL أو الرؤوس أو معلمات الاستعلام أو النص - وأعد الإرسال دون مغادرة Rockxy. لا حلقة نسخ ولصق إلى Postman أو Insomnia أو curl. قم بالتكرار على مطالبات LLM أو تشويش حدود المصادقة أو إعادة إنتاج حالة فاشلة لنقاط نهاية OpenAI وAnthropic وCohere في ثوانٍ.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### قارن

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

قم بتجميع معاملتين تم التقاطهما أو حمولتين ملصقتين جنبًا إلى جنب وحدد كل حقل تغير - الحالة والرؤوس ومفاتيح JSON أو وحدات بايت النص. احصل على انحدارات واجهة برمجة التطبيقات الصامتة، ومخرجات LLM غير الحتمية، وانحراف المطالبات (prompt drift) دون توصيل أي شيء إلى أداة فرق تابعة لجهة خارجية.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### علامات تبويب المعاينة المخصصة

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

تقديم أجسام الطلب والاستجابة بالطريقة التي تريدها. قم بتثبيت علامات تبويب إضافية في المفتش لـ JSON، أو GraphQL، أو JWT، أو الصورة، أو التنسيق الخاص بك - بحيث يمكن إعادة استخدامها عبر كل طلب تم التقاطه.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### الجلسات والتصدير

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

حفظ الجلسات، واستيراد/تصدير HAR للتسليم عبر الأدوات، ونسخ أي طلب بتنسيق cURL أو JSON. قم بتنقيح رؤوس التفويض وملفات تعريف الارتباط والرموز المميزة لحاملها قبل المشاركة - قم بتسليم زميل في الفريق نسخة تجريبية من الأخطاء دون تسريب الأسرار.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### مساحات عمل متعددة علامات التبويب

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="تعرض مساحات عمل Rockxy متعددة علامات التبويب طرق عرض تمت تصفيتها بشكل مستقل لنفس الالتقاط المباشر" width="820" />

احتفظ بعروض تحقيق مستقلة جنبًا إلى جنب لنفس الالتقاط المباشر — علامة تبويب لحركة staging، وواحدة للإنتاج، وواحدة لتدفق جهاز iOS. لكل علامة تبويب عوامل التصفية والفرز والتحديد ونطاق الشريط الجانبي وحالة المفتش الخاصة بها، مع مشاركة الوكيل والمعاملات الملتقطة.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### البرمجة النصية جافا سكريبت

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

ترتبط JS بالطلبات والاستجابات للحالات التي لا يمكن أن تغطيها القاعدة الثابتة - قم بتنقيح معلومات تحديد الهوية الشخصية (PII)، وتوقيع الرموز المميزة، وإعادة كتابة الحمولات. تظهر الأخطاء في السطر بدلاً من إتلاف حركة المرور.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## الفحص المدرك للبروتوكول

يوفر Rockxy فحصًا مدركًا للبروتوكول لحركة AI وWeb3 RPC وx402 ضمن سير عمل تصحيح HTTP المعتاد.

### فحص حركة الذكاء الاصطناعي

يكتشف Rockxy طلبات AI المعترف بها ضمن سير عمل الالتقاط العادي. افحص استدعاءات النماذج المحددة، وحالة البث، وحقول usage عند توفرها، والتحذيرات، وretrieval hints، وملخصات tool-call دون لصق حمولات حساسة في خدمة أخرى.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### فحص Web3/RPC

يحوّل Rockxy مكالمات الشبكة في عصر blockchain إلى أدلة تصحيح قابلة للقراءة. افحص حركة HTTP JSON-RPC بأسلوب EVM وSolana مع provider host وrequest ID وmethod وbatch summary وerror وchain وtransaction وpayload وdebug-intent، دون تحويل Rockxy إلى محفظة أو مستكشف كتل.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### تلميحات تدفق الدفع x402

يبرز Rockxy تلميحات payment-required والموجهة نحو إعادة المحاولة حتى تصبح تدفقات HTTP ذات بوابات الدفع مفهومة من طبقة الشبكة، بينما تبقى أدلة التصحيح محلية وقابلة للتنقيح.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## العمل المستقبلي

تصف الأقسام التالية الاتجاه العام، وليس السلوك الحالي.

### القواعد المدركة للبروتوكول

يمكن لـ Rockxy اليوم بالفعل تسمية وفحص حركة AI وWeb3. تظل مطابقة القواعد الأعمق حسب model أو tool call أو طريقة JSON-RPC أو chain أو transaction hash أو batch subcall عملاً مستقبليًا؛ ولا تزال أدوات تعديل حركة المرور الحالية تطابق URL وطريقة HTTP والرؤوس.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### حزم الأدلة المنقحة `قريبًا`

شارك الحقائق اللازمة لإعادة إنتاج الخلل دون تسريب الأسرار. قم بتعبئة حركة المرور المحددة بملخصات البروتوكول ومعاينات التنقيح والسياق المدعوم بالمصدر الذي يمكن لزميل الفريق تدقيقه.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### مشاركة الفريق والتعاون `قريبًا`

أرسل جلسة تم التقاطها إلى أحد أعضاء الفريق بنقرة واحدة. قم بإضافة تعليقات توضيحية للطلبات الفاشلة بشكل مضمن، ومعرفة من الذي ينظر إلى ماذا في الوقت الفعلي، وتصحيح أخطاء حركة مرور HTTPS بدون مشاركة الشاشة. تستهدف الإصدار المستقبلي.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> غلاف تطبيق macOS أصلي — بلا Electron. SwiftUI + AppKit + SwiftNIO، مع استخدام WebKit فقط لمعاينة جسم HTML.

## بداية سريعة

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

البناء والتشغيل في Xcode. ترشدك نافذة الترحيب خلال عملية إعداد CA الجذر وتثبيت المساعد وتنشيط الوكيل.

**المتطلبات:** ماك 14.0+، Xcode 16+، سويفت 5.9

إذا كنت تريد توصيل Rockxy بعميل MCP محلي بعد التثبيت، فراجع ملف [دليل التكامل MCP](docs/features/mcp.mdx).

## Rockxy مقابل البدائل

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **نموذج المشروع** | AGPL-3.0 مشروع مفتوح المصدر | التطبيق التجاري الخاص | التطبيق التجاري الخاص |
| **كود المصدر** | عام، قابل للتدقيق، قابل للتشعب | مصدر مغلق | مصدر مغلق |
| **البناء من المصدر** | مجانًا مع Xcode من هذا الريبو | غير متوفر من مصدر عام | غير متوفر من مصدر عام |
| **أساس macOS الأصلي** | سويفت + SwiftNIO + SwiftUI/AppKit | تطبيق macOS أصلي مغلق المصدر | تطبيق متعدد المنصات مغلق المصدر |
| **الالتقاط المحلي الأول** | يبقى الوكيل المحلي والشهادات والمساعد وبيانات الالتقاط على جهاز Mac الخاص بك | تطبيق وكيل سطح المكتب | تطبيق وكيل سطح المكتب |
| **سير عمل إعداد المطور** | مركز إعداد المطور المدمج لأوقات التشغيل والعملاء والأجهزة والأطر والبيئات | إعداد تلقائي مدمج بالإضافة إلى أدلة المنصة ووقت التشغيل | أدلة إعداد خاصة بالمنصة |
| **الوكيل الخارجي + توجيه PAC** | وكيل HTTP/HTTPS الرئيسي، والتكوين التلقائي لـ PAC، وقواعد التجاوز | وكيل رئيسي تجاري ودعم PAC | تكوين وكيل رئيسي تجاري |
| **تكامل MCP** | [MCP محلي مدمج](docs/features/mcp.mdx): 10 أدوات للقراءة فقط لحركة المرور والحالة والشهادات وفحص القواعد وتصدير cURL؛ مصادق عليه بالرمز المميز؛ التنقيح مفعّل افتراضيًا | MCP محلي مدمج: فحص حركة المرور بالإضافة إلى أدوات القواعد والجلسات والشهادات والإعداد والتحكم في التطبيق؛ localhost فقط؛ مصادقة بالرمز المميز لكل جلسة؛ تنقيح البيانات الحساسة | لم يُعثر على تكامل MCP من الطرف الأول في [الوثائق الرسمية](https://www.charlesproxy.com/documentation/) التي تمت مراجعتها في 2026-08-13 |
| **AI Assistant أصلي** | مدمج لتحليل حركة المرور للطلب المحدد والطلبات المتعددة داخل Rockxy | غير معروف | غير معروف |
| **فتح مسار المساهمة** | مصدر عام، issues، مناقشات، خارطة طريق، وPRs | متعقب issue عام؛ مصدر التطبيق والإصدارات يتحكم فيهما البائع | وثائق ودعم البائع؛ مصدر التطبيق والإصدارات يتحكم فيهما البائع |

تم التحقق من قدرات المنافسين أعلاه مقابل وثائق المنتج الرسمية في 2026-08-13 وقد تتغير بعد النشر.

على خريطة الطريق: قواعد أعمق مدركة للبروتوكول، وحزم أدلة منقحة أكثر أمانًا، وسير عمل أقوى لإعادة التشغيل والمقارنة، وأدلة Developer Setup أوسع، وبحث مستمر في HTTP/2 وHTTP/3.

## الأمن

يعترض Rockxy حركة مرور الشبكة - الأمان أساسي وليس اختياريًا.

- يقوم مساعد XPC بالتحقق من صحة المتصلين عبر **مقارنة سلسلة الشهادات**، وليس معرف الحزمة فقط
- يتم تشغيل المكونات الإضافية **JavaScriptCore في وضع الحماية** مع مهلة 5 ثوانٍ، لا يمكن الوصول إلى نظام الملفات/الشبكة
- **التحقق من صحة الإدخال** على جميع الحدود - الحدود القصوى لحجم الجسم، وحدود URI، وحماية DoS، ومنع اجتياز المسار
- أوراق الاعتماد **تم تنقيحه تلقائيًا** في السجلات الملتقطة
- الملفات الحساسة المخزنة مع **0o600 أذونات**

الإبلاغ عن نقاط الضعف عبر [الأمن.md](SECURITY.md). انظر [بنية أمنية كاملة](docs/development/security.mdx) للحصول على التفاصيل.

## خريطة الطريق

إن خريطة الطريق العامة لـ Rockxy موجهة نحو سير العمل وخالية من التاريخ. وهو يركز على الموثوقية، وmacOS UX الأصلي، وسير عمل تصحيح الأخطاء، ودعم البروتوكول، ورؤية حركة المرور في عصر AI/Web3، والوثائق، وإعداد المساهمين.

- [خريطة الطريق.md](ROADMAP.md): توجيه هندسي عام رفيع المستوى
- [خريطة الطريق العامة Rockxy](https://github.com/orgs/RockxyApp/projects/1): الرؤية التشغيلية للمشكلات التي تتبعها خارطة الطريق

## التوثيق

الوثائق الكاملة متوفرة في [مستندات روككسي](docs/index.mdx):

- [دليل البدء السريع](docs/quickstart.mdx) - انهض واعمل في دقائق
- [مركز إعداد المطور](docs/features/developer-setup-hub.mdx) — مقتطفات وقت التشغيل، وأدلة الأجهزة، وتحقيقات التحقق من الصحة، ومصفوفة الدعم
- [AI Assistant](docs/features/ai-assistant.mdx) — افحص حركة المرور المحددة محليًا أو باستخدام نموذج مُعد بعد Review Data
- [عوامل التصفية والبحث](docs/core-features/filters-and-search.mdx) — نطاقات الشريط الجانبي وFocus Sets وNoise Control وعوامل تصفية toolbar والبحث
- [فحص AI وWeb3](docs/features/ai-web3-inspection.mdx) — افحص حركة model API وJSON-RPC وx402 المعترف بها
- [التكامل MCP](docs/features/mcp.mdx) — قم بتوصيل Rockxy بعملاء MCP المحليين
- [الهندسة المعمارية](docs/development/architecture.mdx) - محرك الوكيل، نموذج الممثل، تدفق البيانات
- [نموذج الأمان](docs/development/security.mdx) — حدود الثقة، والتحقق من صحة XPC، وإدارة الشهادات
- [قرارات التصميم](docs/development/design-decisions.mdx) — لماذا SwiftNIO، NSTableView، الجهات الفاعلة
- [البناء من المصدر](docs/development/building.mdx) - البناء والاختبار والوبر والتصحيح
- [نمط الكود](docs/development/code-style.mdx) — SwiftLint، وSwiftFormat، والاتفاقيات
- [سجل التغيير](CHANGELOG.md) - الأعمال غير المنشورة والإصدارات الموسومة

## المساهمة

نرحب بالمساهمات - التعليمات البرمجية والاختبارات والمستندات وتقارير الأخطاء وتعليقات تجربة المستخدم.

انظر **[المساهمة.md](CONTRIBUTING.md)** للحصول على تعليمات الإعداد ونمط التعليمات البرمجية وقائمة مراجعة العلاقات العامة الكاملة.

يتم تصنيف القضايا الأولى الجيدة [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). من خلال فتح العلاقات العامة، فإنك توافق على [CLA](CLA.md).

## الرعاة والشركاء

تتم صيانة Rockxy بشكل مستقل. تساعد الرعاية في تمويل التطوير المستمر، وبنية الإصدارات التحتية، والتوثيق، وأعمال الأمان.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

تستضيف [Open Source Collective](https://docs.oscollective.org/) مشروع Rockxy ماليًا. تُسجَّل المساهمات ونفقات المشروع في [صفحة Rockxy العامة على Open Collective](https://opencollective.com/rockxy)، مما يمنح الداعمين رؤية شفافة لكيفية استلام الأموال واستخدامها.

| الفئة | المساهمة | ما الذي تدعمه |
|------|----------|----------------|
| **Backer** | ابتداءً من 5 دولارات شهريًا | صيانة المشروع مفتوح المصدر، والتوثيق، والاختبارات، والإصدارات |
| **Builder** | ابتداءً من 25 دولارًا شهريًا | اختبارات الانحدار، وتحسينات الأداء، ومسارات عمل تصحيح الأخطاء اليومية |
| **Sponsor** | 100 دولار شهريًا | الصيانة طويلة الأمد لأداة تركز على الخصوصية وتظل متاحة مجانًا للمطورين |
| **Sustaining Sponsor** | 500 دولار شهريًا | صيانة وتطوير مركزان، بما في ذلك أتمتة الإصدارات ودعم البروتوكولات |

**استفسارات الشراكة** — شركات أدوات المطورين وشركات الأمان وفرق المؤسسات التي تبحث عن عمليات تكامل مخصصة أو حلول ذات علامة بيضاء: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## الدعم

- [Open Collective](https://opencollective.com/rockxy/donate) - المساهمة في Rockxy من خلال ميزانية المشروع الشفافة
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) - دعم تطوير Rockxy
- [قضايا جيثب](https://github.com/RockxyApp/Rockxy/issues) - تقارير الأخطاء وطلبات الميزات
- [مناقشات جيثب](https://github.com/RockxyApp/Rockxy/discussions) - الأسئلة والدردشة المجتمعية
- **البريد الإلكتروني** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **القضايا الأمنية** - انظر [الأمن.md](SECURITY.md) للإفصاح المسؤول

## الترخيص

[رخصة جنو أفيرو العامة v3.0](LICENSE) — حقوق الطبع والنشر 2024–2026 مملوكة لشركة Rockxy Contributors.

## تاريخ النجوم

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>صنع بواسطة <a href="https://github.com/LocNguyenHuu">Stephen</a>. تم تصميمه باستخدام Swift وSwiftNIO وSwiftUI وAppKit.</sub>
</p>

</div>
