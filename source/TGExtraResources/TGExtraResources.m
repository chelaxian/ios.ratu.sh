// ==========================================================================
// TGExtraResources.m — localization resource shim for sideloaded TGExtra.dylib
// ==========================================================================
// PROBLEM: TGExtra.dylib loads its translations from
//   /Library/Application Support/TGExtra/TGExtra.bundle/...  (jailbreak path)
// which does not exist when the tweak is sideloaded (Sideloadly/TrollFools)
// into Telegram/Swiftgram/Turrit WITHOUT a jailbreak. As a result the UI shows
// raw keys ("GHOST_MODE_SECTION_HEADER") instead of translations, the language
// switcher shows "Failed to load language localization data", and only English
// is selectable.
//
// FIX: this shim embeds ALL 10 language dictionaries compiled in, and at
// runtime swizzles the single translation funnel
//   +[TGExtraLocalization localizedStringForKey:]
// (used by the #define TGLoc(key) macro everywhere in TGExtra) plus the
// language picker
//   -[LanguageSelector viewDidLoad]
//   -[LanguageSelector tableView:didSelectRowAtIndexPath:]
// so the whole tweak works under sideload with no resource bundle present.
//
// Built as a standalone fat (arm64+arm64e) dylib. Inject it ALONGSIDE
// TGExtra.dylib (Sideloadly/TrollFools support multiple dylibs). It must run
// its setup AFTER TGExtra's classes are registered, so setup is deferred via
// dispatch_after.
//
// Generated from waruhachi/TGExtra TGExtra.bundle. Do not hand-edit.
// ==========================================================================

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// ---- Telegram's own classes (resolved at runtime) -------------------------
@interface TGLocalization : NSObject
- (NSString *)get:(NSString *)queryString;
- (id)initWithVersion:(int)a code:(id)b dict:(id)c isActive:(BOOL)d;
@end

// ---- TGExtra's classes (resolved at runtime; we swizzle these) -----------
@interface TGExtraLocalization : NSObject
@property (nonatomic, strong) TGLocalization *localization;
+ (instancetype)shared;
+ (NSString *)localizedStringForKey:(NSString *)key;
@end

@interface LanguageSelector : UIViewController
@property (nonatomic, strong) NSArray *languages;
@end

// ==========================================================================
// Embedded translations (all 10 languages)
// ==========================================================================

static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *TGXAllTranslations;
static NSString *TGXCurrentLang;  // current language code, e.g. "en", "ru"

static void TGXLoadTranslations(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
    // ar: 64 keys
    NSDictionary *dict_ar = @{
        @"APPLY": @"تطبيق",
        @"APPLY_CHANGES": @"هل أنت متأكد أنك تريد تطبيق هذه التغييرات؟",
        @"AUTHOR_MESSAGE": @"هذا التعديل على تيليجرام مخصص للاستخدام الشخصي والتعليمي فقط. نحن لسنا تابعين لتيليجرام بأي شكل من الأشكال. جميع العلامات التجارية، بما في ذلك اسم تيليجرام وشعاره، تعود لأصحابها. لا تستخدم هذا التعديل لكسر القوانين أو القيام بأي شيء مريب أو مخالف لشروط استخدام تيليجرام — نحن غير مسؤولين إذا حدث أي شيء غير متوقع. استخدمه على مسؤوليتك الخاصة.\n\nأيضًا... إذا أعجبك، قل شيئًا. أنا حرفيًا أعيش على التقدير.\n\nوإذا كنت ترغب في دعمي بالتبرع بدولار أو اثنين، تواصل معي على تيليجرام.",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"هل أنت متأكد؟",
        @"CACHE_CLEAR_WARNING_TITLE": @"تأكيد",
        @"CANCEL": @"إلغاء",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"لأن منتقي الملفات ينسخ الملفات إلى مجلد مؤقت، يجب مسحها يدوياً",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"مسح ذاكرة منتقي الملفات المؤقتة",
        @"CREDITS_SECTION_HEADER": @"الاعتمادات",
        @"DISABLE_ALL_ADS_SUBTITLE": @"إزالة الإعلانات والمحتوى الترويجي من التطبيق.",
        @"DISABLE_ALL_ADS_TITLE": @"تعطيل جميع الإعلانات",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"عدم عرض أنك تقوم باختيار جهة اتصال.",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"تعطيل اختيار جهة الاتصال",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"عدم عرض أنك تقوم باختيار موقع.",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"تعطيل اختيار الموقع",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"عدم عرض أنك تقوم باختيار ملصق.",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"تعطيل اختيار الملصق",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"عدم عرض أنك قمت بإقرار الإيموجي.",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"تعطيل إقرار الإيموجي",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"عدم عرض أنك تتفاعل مع إيموجي.",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"تعطيل التفاعل مع الإيموجي",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"عدم إظهار أنك قرأت الرسالة.",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"تعطيل إيصالات قراءة الرسائل",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"عدم عرض حالتك كأونلاين.",
        @"DISABLE_ONLINE_STATUS_TITLE": @"تعطيل حالة الإنترنت",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"عدم عرض أنك تلعب لعبة.",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"تعطيل حالة اللعب",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"عدم عرض أنك تقوم بتسجيل فيديو دائري.",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"تعطيل تسجيل الفيديو الدائري",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"عدم عرض أنك تقوم بتسجيل فيديو.",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"تعطيل حالة تسجيل الفيديو",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"عدم عرض أنك تتحدث في مكالمة جماعية.",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"تعطيل التحدث في المكالمات الجماعية",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"عدم إظهار أنك شاهدت القصة.",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"تعطيل إيصالات قراءة القصص",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"عدم عرض أنك تقوم بكتابة رسالة.",
        @"DISABLE_TYPING_STATUS_TITLE": @"تعطيل حالة الكتابة",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"عدم عرض أنك تقوم بتحميل ملف.",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"تعطيل حالة تحميل الملفات",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"إخفاء عند تحميل صورة",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"تعطيل حالة تحميل الصور",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"تعطيل حالة تحميل الفيديو الدائري",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"إخفاء عند تحميل فيديو",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"تعطيل حالة تحميل الفيديو",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"عدم عرض أنك تقوم بتسجيل رسالة صوتية.",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"تعطيل تسجيل الرسائل الصوتية",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"عدم عرض أنك تقوم بتحميل رسالة صوتية.",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"تعطيل حالة تحميل الرسائل الصوتية",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"يسمح لك بتزييف موقع GPS الخاص بجهازك",
        @"ENABLE_FAKE_LOCATION_TITLE": @"تمكين تزييف الموقع",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"تجاوز القيود وحفظ المحتوى المحمي.",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"تمكين حفظ المحتوى المحمي",
        @"FAKE_LOCATION_SECTION_HEADER": @"موقع وهمي",
        @"FILE_FIXER_SECTION_HEADER": @"إصلاح منتقي الملفات",
        @"FIX_FILE_PICKER_SUBTITLE": @"يصلح المشكلة التي تمنع اختيار الملفات من تطبيق الملفات في النسخ الجانبية",
        @"FIX_FILE_PICKER_TITLE": @"إصلاح منتقي الملفات",
        @"GHOST_MODE_SECTION_HEADER": @"وضع الشبح",
        @"LANGUAGE_SECTION_HEADER": @"اللغة",
        @"MISC": @"متفرقات",
        @"MISC_SECTION_HEADER": @"متنوع",
        @"OK": @"موافق",
        @"READ_RECEIPTS": @"إيصالات القراءة",
        @"READ_RECEIPT_SECTION_HEADER": @"إيصالات القراءة",
        @"SELECT_FAKE_LOCATION_TITLE": @"اختر الموقع",
    };
    // cn: 64 keys
    NSDictionary *dict_cn = @{
        @"APPLY": @"应用",
        @"APPLY_CHANGES": @"您确定要应用这些更改吗？",
        @"AUTHOR_MESSAGE": @"此 Telegram 插件仅供个人和教育用途。我们与 Telegram 没有任何关联。所有商标，包括 Telegram 的名称和标志，均归其各自所有者所有。请不要用它来违反规则、做灰色操作或违反 Telegram 的服务条款——如果出问题，我们概不负责。使用风险自负。\n\n另外……如果你喜欢这个插件，记得说一声。我真的很需要认可来维持动力。\n\n还有……如果你愿意支持我，捐个一两美元的话，可以在 Telegram 上联系我。",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"你确定吗？",
        @"CACHE_CLEAR_WARNING_TITLE": @"确认",
        @"CANCEL": @"取消",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"由于文件选择器会将文件复制到临时目录，需要手动清除",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"清除文件选择器缓存",
        @"CREDITS_SECTION_HEADER": @"致谢",
        @"DISABLE_ALL_ADS_SUBTITLE": @"移除应用中的广告和推广内容。",
        @"DISABLE_ALL_ADS_TITLE": @"关闭所有广告",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"隐藏你正在选择联系人的状态。",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"隐藏选择联系人状态",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"隐藏你正在选择位置的状态。",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"隐藏选择位置状态",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"隐藏你正在选择贴纸的状态。",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"隐藏选择贴纸状态",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"隐藏你用表情回应消息时的状态。",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"隐藏表情反应状态",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"隐藏你与表情互动时的状态。",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"隐藏表情互动状态",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"防止他人知道你已阅读消息。",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"关闭消息已读回执",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"防止他人看到你在线。",
        @"DISABLE_ONLINE_STATUS_TITLE": @"隐藏在线状态",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"隐藏你正在玩游戏的状态。",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"隐藏游戏状态",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"隐藏你正在录制圆形视频的状态。",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"隐藏圆形视频录制状态",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"隐藏你正在录制视频时的状态。",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"隐藏视频录制状态",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"隐藏你在群组通话中发言时的状态。",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"隐藏群组通话发言状态",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"防止他人知道你已查看故事。",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"关闭故事已读回执",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"隐藏你正在输入的信息状态。",
        @"DISABLE_TYPING_STATUS_TITLE": @"隐藏输入状态",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"隐藏你正在上传文件的状态。",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"隐藏文件上传状态",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"上传照片时隐藏状态",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"隐藏照片上传状态",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"隐藏圆形视频上传状态",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"上传视频时隐藏状态",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"隐藏视频上传状态",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"隐藏你正在录制语音消息时的状态。",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"隐藏语音消息录制状态",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"隐藏你正在上传语音消息时的状态。",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"隐藏语音消息上传状态",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"允许伪装设备的 GPS 位置",
        @"ENABLE_FAKE_LOCATION_TITLE": @"启用虚拟位置",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"绕过限制，保存受保护的内容。",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"允许保存受保护内容",
        @"FAKE_LOCATION_SECTION_HEADER": @"虚拟位置",
        @"FILE_FIXER_SECTION_HEADER": @"文件选择器修复",
        @"FIX_FILE_PICKER_SUBTITLE": @"修复在侧载版本中无法从文件应用选择文件的问题",
        @"FIX_FILE_PICKER_TITLE": @"修复文件选择器",
        @"GHOST_MODE_SECTION_HEADER": @"隐身模式",
        @"LANGUAGE_SECTION_HEADER": @"语言",
        @"MISC": @"其他",
        @"MISC_SECTION_HEADER": @"其他",
        @"OK": @"确定",
        @"READ_RECEIPTS": @"已读回执",
        @"READ_RECEIPT_SECTION_HEADER": @"阅读回执",
        @"SELECT_FAKE_LOCATION_TITLE": @"选择位置",
    };
    // en: 65 keys
    NSDictionary *dict_en = @{
        @"APPLY": @"Apply",
        @"APPLY_CHANGES": @"Are you sure you want to Apply These Changes",
        @"AUTHOR_MESSAGE": @"This Telegram tweak is for personal and educational use only. We are not affiliated with Telegram in any way. All trademarks, including the Telegram name and logo, belong to their respective owners. Don’t use this to break rules, be shady, or violate Telegram’s terms—we’re not responsible if things go sideways. Use at your own risk. \n \nAlso… if you like it, say something. I seriously live off validation. \n \nAlso.. If you Want to support me by donating a dollar or Two, Contact me on Telegram",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"Are you sure?",
        @"CACHE_CLEAR_WARNING_TITLE": @"Confirm",
        @"CANCEL": @"Cancel",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"Because File Picker Copies the files to temporory directory, we have to clear it manually",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"Clear File Picker Cache",
        @"CREDITS_SECTION_HEADER": @"Credits",
        @"DISABLE_ALL_ADS_SUBTITLE": @"Remove promotional content and ads from the app.",
        @"DISABLE_ALL_ADS_TITLE": @"Disable All Ads",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"Hide when you're choosing a contact.",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"Disable Choosing Contact",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"Hide when you're choosing a location.",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"Disable Choosing Location Status",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"Hide when you're picking a sticker.",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"Disable Choosing Sticker Status",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"Hide when you react with emoji to a message.",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"Disable Emoji Acknowledgement Status",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"Hide when you interact with emoji.",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"Disable Emoji Interaction Status",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"Prevent others from seeing you've read their messages.",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"Disable Message Read Receipts",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"Prevent others from seeing you online.",
        @"DISABLE_ONLINE_STATUS_TITLE": @"Disable Online Status",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"Hide when you're playing a game.",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"Disable Playing Game Status",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"Hide when you're recording a round video.",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"Disable Recording Round Video Status",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"Hide when you're recording a video.",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"Disable Recording Video Status",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"Hide when you're speaking in a group call.",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"Disable Speaking in Group Call Status",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"Prevent others from seeing you've viewed their stories.",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"Disable Story Read Receipts",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"Hide when you're typing messages.",
        @"DISABLE_TYPING_STATUS_TITLE": @"Disable Typing Status",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"Hide when you're uploading a file.",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"Disable Uploading File Status",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"Hide when you're uploading a Photo",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"Disable Uploading Photo Status",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"Disable Uploading Round Video Status",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"Hide when you're uploading a Video",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"Disable Uploading Video Status",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"Hide when you're recording a voice message.",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"Disable Voice Message Recording Status",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"Hide when you're uploading a voice message.",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"Disable Voice Message Uploading Status",
        @"DISCLAIMER": @"Disclaimer",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"Allows you to spoof your device's GPS Location",
        @"ENABLE_FAKE_LOCATION_TITLE": @"Enable Location Spoofing",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"Bypass restrictions on saving protected content.",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"Allow Saving Protected Content",
        @"FAKE_LOCATION_SECTION_HEADER": @"Fake Location",
        @"FILE_FIXER_SECTION_HEADER": @"File Picker Fix",
        @"FIX_FILE_PICKER_SUBTITLE": @"Fixes the issue where you can't pick files from Files App On Sideloaded Versions",
        @"FIX_FILE_PICKER_TITLE": @"Fix File Picker",
        @"GHOST_MODE_SECTION_HEADER": @"Ghost Mode",
        @"LANGUAGE_SECTION_HEADER": @"Language",
        @"MISC": @"Miscellaneous",
        @"MISC_SECTION_HEADER": @"Misc",
        @"OK": @"Ok",
        @"READ_RECEIPTS": @"Read Receipts",
        @"READ_RECEIPT_SECTION_HEADER": @"Read Receipts",
        @"SELECT_FAKE_LOCATION_TITLE": @"Select Location",
    };
    // fr: 64 keys
    NSDictionary *dict_fr = @{
        @"APPLY": @"Appliquer",
        @"APPLY_CHANGES": @"Êtes-vous sûr de vouloir appliquer ces changements ?",
        @"AUTHOR_MESSAGE": @"Ce tweak Telegram est uniquement destiné à un usage personnel et éducatif. Nous ne sommes en aucun cas affiliés à Telegram. Toutes les marques, y compris le nom et le logo de Telegram, appartiennent à leurs propriétaires respectifs. N'utilisez pas ceci pour enfreindre les règles, faire des choses louches ou violer les conditions d'utilisation de Telegram — nous ne sommes pas responsables en cas de problème. Utilisez-le à vos risques et périls.\n\nAussi… si ça vous plaît, dites-le. Sérieusement, je vis pour la validation.\n\nEt… si vous voulez me soutenir avec un ou deux euros, contactez-moi sur Telegram.",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"Êtes-vous sûr ?",
        @"CACHE_CLEAR_WARNING_TITLE": @"Confirmer",
        @"CANCEL": @"Annuler",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"Comme le sélecteur copie les fichiers dans un dossier temporaire, il faut le vider manuellement",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"Vider le Cache du Sélecteur de Fichiers",
        @"CREDITS_SECTION_HEADER": @"Crédits",
        @"DISABLE_ALL_ADS_SUBTITLE": @"Supprimer les publicités et le contenu sponsorisé de l'application.",
        @"DISABLE_ALL_ADS_TITLE": @"Désactiver toutes les publicités",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"Ne pas afficher que vous êtes en train de choisir un contact.",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"Désactiver le choix du contact",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train de choisir un lieu.",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"Désactiver le choix du lieu",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train de choisir un sticker.",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"Désactiver le choix de stickers",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"Ne pas afficher que vous avez reconnu un émoji.",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"Désactiver la reconnaissance des émojis",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"Ne pas afficher que vous interagissez avec un émoji.",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"Désactiver l'interaction avec les émojis",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"Ne pas afficher que vous avez lu le message.",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"Désactiver les accusés de réception de message",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en ligne.",
        @"DISABLE_ONLINE_STATUS_TITLE": @"Désactiver le statut en ligne",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train de jouer.",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"Désactiver le statut de jeu",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train d'enregistrer une vidéo ronde.",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"Désactiver l'enregistrement de vidéo ronde",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train d'enregistrer une vidéo.",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"Désactiver le statut d'enregistrement vidéo",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"Ne pas afficher que vous parlez dans un appel de groupe.",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"Désactiver le statut de parole dans les appels de groupe",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"Ne pas afficher que vous avez vu la story.",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"Désactiver les accusés de réception des stories",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train d'écrire.",
        @"DISABLE_TYPING_STATUS_TITLE": @"Désactiver le statut de saisie",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train de télécharger un fichier.",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"Désactiver le statut de téléchargement de fichier",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"Masquer lors du téléchargement d'une photo",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"Désactiver le statut de téléchargement de photo",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"Désactiver le statut de téléchargement de vidéo ronde",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"Masquer lors du téléchargement d'une vidéo",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"Désactiver le statut de téléchargement de vidéo",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train d'enregistrer un message vocal.",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"Désactiver l'enregistrement de messages vocaux",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"Ne pas afficher que vous êtes en train de télécharger un message vocal.",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"Désactiver le statut de téléchargement de message vocal",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"Permet de simuler la localisation GPS de votre appareil",
        @"ENABLE_FAKE_LOCATION_TITLE": @"Activer la Fausse Localisation",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"Contournement des restrictions pour enregistrer le contenu protégé.",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"Activer l'enregistrement de contenu protégé",
        @"FAKE_LOCATION_SECTION_HEADER": @"Fausse Localisation",
        @"FILE_FIXER_SECTION_HEADER": @"Correcteur de Sélecteur de Fichiers",
        @"FIX_FILE_PICKER_SUBTITLE": @"Corrige le problème empêchant la sélection de fichiers depuis l’app Fichiers sur les versions installées manuellement",
        @"FIX_FILE_PICKER_TITLE": @"Corriger le Sélecteur de Fichiers",
        @"GHOST_MODE_SECTION_HEADER": @"Mode Fantôme",
        @"LANGUAGE_SECTION_HEADER": @"Langue",
        @"MISC": @"Divers",
        @"MISC_SECTION_HEADER": @"Divers",
        @"OK": @"OK",
        @"READ_RECEIPTS": @"Accusés de réception",
        @"READ_RECEIPT_SECTION_HEADER": @"Accusés de Lecture",
        @"SELECT_FAKE_LOCATION_TITLE": @"Sélectionner une Localisation",
    };
    // it: 65 keys
    NSDictionary *dict_it = @{
        @"APPLY": @"Applica",
        @"APPLY_CHANGES": @"Sei sicuro di voler applicare queste modifiche?",
        @"AUTHOR_MESSAGE": @"Questa modifica per Telegram è solo per uso personale ed educativo. Non siamo in alcun modo affiliati con Telegram. Tutti i marchi, incluso il nome e il logo di Telegram, appartengono ai rispettivi proprietari. Non usare questo tweak per infrangere le regole, fare i furbi o violare i termini di Telegram — non siamo responsabili se qualcosa va storto. Usalo a tuo rischio e pericolo. \n\nInoltre… se ti piace, fammelo sapere. Vivo seriamente di approvazione. \n\nE se vuoi supportarmi con una donazione di uno o due dollari, contattami su Telegram.",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"Sei sicuro?",
        @"CACHE_CLEAR_WARNING_TITLE": @"Conferma",
        @"CANCEL": @"Annulla",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"Poiché il selettore file copia i file in una directory temporanea, dobbiamo svuotarla manualmente",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"Svuota cache selezione file",
        @"CREDITS_SECTION_HEADER": @"Crediti",
        @"DISABLE_ALL_ADS_SUBTITLE": @"Rimuove contenuti promozionali e annunci dall'app.",
        @"DISABLE_ALL_ADS_TITLE": @"Disattiva tutti gli annunci",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"Nascondi quando stai scegliendo un contatto.",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"Disattiva selezione contatto",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"Nascondi quando stai scegliendo una posizione.",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"Disattiva stato di selezione posizione",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"Nascondi quando stai scegliendo uno sticker.",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"Disattiva stato di selezione sticker",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"Nascondi quando reagisci con un'emoji a un messaggio.",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"Disattiva stato di reazione con emoji",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"Nascondi quando interagisci con un'emoji.",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"Disattiva stato di interazione con emoji",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"Impedisci agli altri di vedere che hai letto i loro messaggi.",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"Disattiva conferme di lettura messaggi",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"Impedisci agli altri di vederti online.",
        @"DISABLE_ONLINE_STATUS_TITLE": @"Disattiva stato online",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"Nascondi quando stai giocando.",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"Disattiva stato di gioco",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"Nascondi quando stai registrando un video rotondo.",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"Disattiva stato di registrazione video rotondo",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"Nascondi quando stai registrando un video.",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"Disattiva stato di registrazione video",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"Nascondi quando stai parlando in una chiamata di gruppo.",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"Disattiva stato di parola in chiamata di gruppo",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"Impedisci agli altri di vedere che hai visualizzato le loro storie.",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"Disattiva conferme di lettura storie",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"Nascondi quando stai scrivendo messaggi.",
        @"DISABLE_TYPING_STATUS_TITLE": @"Disattiva stato di digitazione",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"Nascondi quando stai caricando un file.",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"Disattiva stato di caricamento file",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"Nascondi quando stai caricando una foto",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"Disattiva stato di caricamento foto",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"Disattiva stato di caricamento video rotondo",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"Nascondi quando stai caricando un video",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"Disattiva stato di caricamento video",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"Nascondi quando stai registrando un messaggio vocale.",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"Disattiva stato di registrazione messaggio vocale",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"Nascondi quando stai caricando un messaggio vocale.",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"Disattiva stato di caricamento messaggio vocale",
        @"DISCLAIMER": @"Avvertenza",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"Ti consente di falsificare la posizione GPS del dispositivo",
        @"ENABLE_FAKE_LOCATION_TITLE": @"Abilita falsificazione posizione",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"Bypassa le restrizioni sul salvataggio dei contenuti protetti.",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"Consenti salvataggio contenuti protetti",
        @"FAKE_LOCATION_SECTION_HEADER": @"Posizione falsa",
        @"FILE_FIXER_SECTION_HEADER": @"Correzione selezione file",
        @"FIX_FILE_PICKER_SUBTITLE": @"Corregge il problema per cui non puoi selezionare file dall'app File nelle versioni sideloaded",
        @"FIX_FILE_PICKER_TITLE": @"Correggi selezione file",
        @"GHOST_MODE_SECTION_HEADER": @"Modalità Fantasma",
        @"LANGUAGE_SECTION_HEADER": @"Lingua",
        @"MISC": @"Varie",
        @"MISC_SECTION_HEADER": @"Varie",
        @"OK": @"Ok",
        @"READ_RECEIPTS": @"Conferme di lettura",
        @"READ_RECEIPT_SECTION_HEADER": @"Conferme di lettura",
        @"SELECT_FAKE_LOCATION_TITLE": @"Seleziona posizione",
    };
    // ja: 65 keys
    NSDictionary *dict_ja = @{
        @"APPLY": @"適用",
        @"APPLY_CHANGES": @"これらの変更を適用してもよろしいですか",
        @"AUTHOR_MESSAGE": @"このTweakは個人的かつ教育目的のみで提供されており、Telegram とは一切関係がありません。Telegram の名称やロゴなどの商標はそれぞれの所有者に帰属します。違反行為や規約違反に使わないでください。何か問題が発生しても開発者は責任を負いません。すべて自己責任でご使用ください。\n \nそれと、もし気に入ったら何か感想をください。正直、評価が励みになります。\n \nまた、1～2ドル寄付してサポートしたい場合は、Telegramで連絡してください。",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"本当によろしいですか？",
        @"CACHE_CLEAR_WARNING_TITLE": @"確認",
        @"CANCEL": @"キャンセル",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"ファイルピッカーはファイルを一時ディレクトリにコピーするため、手動でクリアする必要があります。",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"ファイルピッカーのキャッシュをクリア",
        @"CREDITS_SECTION_HEADER": @"クレジット",
        @"DISABLE_ALL_ADS_SUBTITLE": @"アプリからプロモーションコンテンツと広告を削除します。",
        @"DISABLE_ALL_ADS_TITLE": @"全ての広告を無効化",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"連絡先を選択中であることを隠します。",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"連絡先選択中表示を無効化",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"位置情報を選択中であることを隠します。",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"位置情報選択中表示を無効化",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"ステッカーを選択中であることを隠します。",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"ステッカー選択中表示を無効化",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"メッセージに絵文字でリアクションしたことを隠します。",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"絵文字リアクション表示を無効化",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"絵文字を操作中であることを隠します。",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"絵文字操作中表示を無効化",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"メッセージを読んだことを相手に通知しません。",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"メッセージ既読通知を無効化",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"他のユーザーにオンライン状態を表示しません。",
        @"DISABLE_ONLINE_STATUS_TITLE": @"オンライン表示を無効化",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"ゲームプレイ中であることを隠します。",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"ゲームプレイ中表示を無効化",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"ラウンド動画を録画中であることを隠します。",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"ラウンド動画録画中表示を無効化",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"動画を録画中であることを隠します。",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"動画録画中表示を無効化",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"グループ通話で発言中であることを隠します。",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"グループ通話発言中表示を無効化",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"ストーリーを見たことを相手に通知しません。",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"ストーリー既読通知を無効化",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"メッセージ入力中の表示を隠します。",
        @"DISABLE_TYPING_STATUS_TITLE": @"入力中表示を無効化",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"ファイルをアップロード中であることを隠します。",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"ファイルアップロード中表示を無効化",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"写真をアップロード中であることを隠します",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"写真アップロード中表示を無効化",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"ラウンド動画アップロード中表示を無効化",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"動画をアップロード中であることを隠します",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"動画アップロード中表示を無効化",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"ボイスメッセージを録音中であることを隠します。",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"ボイスメッセージ録音中表示を無効化",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"ボイスメッセージをアップロード中であることを隠します。",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"ボイスメッセージアップロード中表示を無効化",
        @"DISCLAIMER": @"免責事項",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"デバイスのGPS位置情報を偽装することができます",
        @"ENABLE_FAKE_LOCATION_TITLE": @"位置情報の偽装を有効化",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"保存が制限されているコンテンツも保存できるようにします。",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"保護されたコンテンツの保存を許可",
        @"FAKE_LOCATION_SECTION_HEADER": @"位置情報の偽装",
        @"FILE_FIXER_SECTION_HEADER": @"ファイル選択の修正",
        @"FIX_FILE_PICKER_SUBTITLE": @"サイドロード版でファイルアプリからファイルを選択できない問題を修正します。",
        @"FIX_FILE_PICKER_TITLE": @"ファイルピッカーを修正",
        @"GHOST_MODE_SECTION_HEADER": @"ゴーストモード",
        @"LANGUAGE_SECTION_HEADER": @"言語",
        @"MISC": @"その他",
        @"MISC_SECTION_HEADER": @"その他",
        @"OK": @"OK",
        @"READ_RECEIPTS": @"既読通知",
        @"READ_RECEIPT_SECTION_HEADER": @"既読通知",
        @"SELECT_FAKE_LOCATION_TITLE": @"位置情報を選択",
    };
    // ru: 65 keys
    NSDictionary *dict_ru = @{
        @"APPLY": @"Применить",
        @"APPLY_CHANGES": @"Вы уверены, что хотите применить эти изменения?",
        @"AUTHOR_MESSAGE": @"Этот твик для Telegram предназначен только для личного и образовательного использования. Мы никоим образом не связаны с Telegram. Все торговые марки, включая название и логотип Telegram, принадлежат их владельцам. Не используйте это для нарушения правил, сомнительных действий или нарушений условий использования Telegram — мы не несем ответственности, если что-то пойдет не так. Используйте на свой страх и риск.\n\nА ещё… если тебе понравилось — скажи об этом. Я, честно говоря, питаюсь одобрением.\n\nИ… если хочешь поддержать меня и скинуть доллар-другой, напиши мне в Telegram.",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"Вы уверены?",
        @"CACHE_CLEAR_WARNING_TITLE": @"Подтвердить",
        @"CANCEL": @"Отмена",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"Поскольку файлы копируются в временную папку, кэш нужно очищать вручную",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"Очистить кэш выбора файлов",
        @"CREDITS_SECTION_HEADER": @"Благодарности",
        @"DISABLE_ALL_ADS_SUBTITLE": @"Удалить рекламу и промо-контент из приложения.",
        @"DISABLE_ALL_ADS_TITLE": @"Отключить всю рекламу",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"Не показывать, что вы выбираете контакт.",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"Скрыть выбор контакта",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"Не показывать, что вы выбираете местоположение.",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"Скрыть выбор локации",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"Не показывать, что вы выбираете стикер.",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"Скрыть выбор стикера",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"Не показывать, что вы реагируете на сообщение эмодзи.",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"Скрыть реакцию эмодзи",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"Не показывать, что вы взаимодействуете с эмодзи.",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"Скрыть взаимодействие с эмодзи",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"Не сообщать, что вы прочитали сообщение.",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"Отключить отчёты о прочтении сообщений",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"Не показывать другим, что вы в сети.",
        @"DISABLE_ONLINE_STATUS_TITLE": @"Скрыть онлайн-статус",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"Не показывать, что вы играете в игру.",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"Скрыть игру",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"Не показывать, что вы записываете круглое видео.",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"Скрыть запись круглого видео",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"Не показывать, что вы записываете видео.",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"Скрыть статус записи видео",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"Не показывать, что вы говорите в групповом звонке.",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"Скрыть голос в групповом звонке",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"Не сообщать, что вы просмотрели историю.",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"Отключить отчёты о прочтении историй",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"Не показывать, что вы печатаете сообщение.",
        @"DISABLE_TYPING_STATUS_TITLE": @"Скрыть статус набора",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"Не показывать, что вы загружаете файл.",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"Скрыть статус загрузки файла",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"Скрывать при загрузке фото",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"Скрыть статус загрузки фото",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"Скрыть загрузку круглого видео",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"Скрывать при загрузке видео",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"Скрыть статус загрузки видео",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"Не показывать, что вы записываете голосовое сообщение.",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"Скрыть запись голосового сообщения",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"Не показывать, что вы загружаете голосовое сообщение.",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"Скрыть загрузку голосового сообщения",
        @"DISCLAIMER": @"Отказ от ответственности",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"Позволяет подделывать GPS-локацию устройства",
        @"ENABLE_FAKE_LOCATION_TITLE": @"Включить фейковую геолокацию",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"Обойти ограничения и сохранить защищённый контент.",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"Разрешить сохранение защищённого контента",
        @"FAKE_LOCATION_SECTION_HEADER": @"Фейковая геолокация",
        @"FILE_FIXER_SECTION_HEADER": @"Исправление выбора файлов",
        @"FIX_FILE_PICKER_SUBTITLE": @"Исправляет ошибку, из-за которой невозможно выбрать файлы из приложения 'Файлы' на установленных вручную версиях",
        @"FIX_FILE_PICKER_TITLE": @"Исправить выбор файлов",
        @"GHOST_MODE_SECTION_HEADER": @"Режим призрака",
        @"LANGUAGE_SECTION_HEADER": @"Язык",
        @"MISC": @"Разное",
        @"MISC_SECTION_HEADER": @"Разное",
        @"OK": @"Ок",
        @"READ_RECEIPTS": @"Отчёты о прочтении",
        @"READ_RECEIPT_SECTION_HEADER": @"Отчёты о прочтении",
        @"SELECT_FAKE_LOCATION_TITLE": @"Выбрать местоположение",
    };
    // es: 65 keys
    NSDictionary *dict_es = @{
        @"APPLY": @"Aplicar",
        @"APPLY_CHANGES": @"¿Estás seguro de que quieres aplicar estos cambios?",
        @"AUTHOR_MESSAGE": @"Este ajuste de Telegram es solo para uso personal y educativo. No estamos afiliados con Telegram de ninguna manera. Todas las marcas registradas, incluido el nombre y logo de Telegram, pertenecen a sus respectivos propietarios. No uses esto para romper reglas, hacer cosas sospechosas o violar los términos de Telegram — no nos hacemos responsables si algo sale mal. Úsalo bajo tu propio riesgo.\n\nAdemás... si te gusta, dilo. En serio, vivo del reconocimiento.\n\nY también... si quieres apoyarme donando uno o dos dólares, contáctame por Telegram.",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"¿Estás seguro?",
        @"CACHE_CLEAR_WARNING_TITLE": @"Confirmar",
        @"CANCEL": @"Cancelar",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"Como el selector copia los archivos a un directorio temporal, debemos borrarlos manualmente",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"Borrar Caché del Selector de Archivos",
        @"CREDITS_SECTION_HEADER": @"Créditos",
        @"DISABLE_ALL_ADS_SUBTITLE": @"Eliminar los anuncios y el contenido patrocinado de la aplicación.",
        @"DISABLE_ALL_ADS_TITLE": @"Desactivar todos los anuncios",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"No mostrar que estás eligiendo un contacto.",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"Desactivar selección de contacto",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"No mostrar que estás eligiendo una ubicación.",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"Desactivar selección de ubicación",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"No mostrar que estás eligiendo un sticker.",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"Desactivar selección de stickers",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"No mostrar que has reconocido un emoji.",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"Desactivar reconocimiento de emojis",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"No mostrar que estás interactuando con un emoji.",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"Desactivar interacción con emojis",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"No mostrar que has leído el mensaje.",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"Desactivar recibos de lectura de mensajes",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"No mostrar que estás en línea.",
        @"DISABLE_ONLINE_STATUS_TITLE": @"Desactivar estado en línea",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"No mostrar que estás jugando.",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"Desactivar estado de juego",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"No mostrar que estás grabando un video redondo.",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"Desactivar grabación de video redondo",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"No mostrar que estás grabando un video.",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"Desactivar estado de grabación de video",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"No mostrar que estás hablando en una llamada grupal.",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"Desactivar estado de habla en llamada grupal",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"No mostrar que has visto la historia.",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"Desactivar recibos de lectura de historias",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"No mostrar que estás escribiendo.",
        @"DISABLE_TYPING_STATUS_TITLE": @"Desactivar estado de escritura",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"No mostrar que estás subiendo un archivo.",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"Desactivar estado de carga de archivo",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"Ocultar al subir una foto",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"Desactivar estado de carga de foto",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"Desactivar estado de carga de video redondo",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"Ocultar al subir un video",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"Desactivar estado de carga de video",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"No mostrar que estás grabando un mensaje de voz.",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"Desactivar grabación de mensajes de voz",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"No mostrar que estás subiendo un mensaje de voz.",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"Desactivar estado de carga de mensaje de voz",
        @"DISCLAIMER": @"Aviso legal",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"Permite falsificar la ubicación GPS del dispositivo",
        @"ENABLE_FAKE_LOCATION_TITLE": @"Activar Ubicación Falsa",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"Eludir restricciones para guardar contenido protegido.",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"Activar guardado de contenido protegido",
        @"FAKE_LOCATION_SECTION_HEADER": @"Ubicación Falsa",
        @"FILE_FIXER_SECTION_HEADER": @"Reparador de Selector de Archivos",
        @"FIX_FILE_PICKER_SUBTITLE": @"Soluciona el problema que impide seleccionar archivos desde la app Archivos en versiones instaladas manualmente",
        @"FIX_FILE_PICKER_TITLE": @"Reparar Selector de Archivos",
        @"GHOST_MODE_SECTION_HEADER": @"Modo Fantasma",
        @"LANGUAGE_SECTION_HEADER": @"Idioma",
        @"MISC": @"Varios",
        @"MISC_SECTION_HEADER": @"Misceláneo",
        @"OK": @"Aceptar",
        @"READ_RECEIPTS": @"Recibos de lectura",
        @"READ_RECEIPT_SECTION_HEADER": @"Confirmaciones de Lectura",
        @"SELECT_FAKE_LOCATION_TITLE": @"Seleccionar Ubicación",
    };
    // tw: 65 keys
    NSDictionary *dict_tw = @{
        @"APPLY": @"套用",
        @"APPLY_CHANGES": @"你確定要套用這些變更嗎？",
        @"AUTHOR_MESSAGE": @"本Telegram調整工具僅限於個人及教育用途。我們與Telegram無任何關聯。所有商標，包括Telegram名稱及標誌，皆屬其各自所有者所有。請勿使用本工具違反規則、進行不當行為或違反Telegram的服務條款。若因使用本工具而產生任何問題，我們概不負責，使用者須自行承擔風險。\n \n此外，若您對本工具感到滿意，歡迎提供意見或反饋，您的支持對我們至關重要。\n \n如有意透過小額捐款支持我，請透過Telegram與我聯繫。",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"你確定嗎？",
        @"CACHE_CLEAR_WARNING_TITLE": @"確認",
        @"CANCEL": @"取消",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"由於檔案選擇器會將檔案複製到臨時目錄，需手動清除快取",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"清除檔案選擇器快取",
        @"CREDITS_SECTION_HEADER": @"鳴謝",
        @"DISABLE_ALL_ADS_SUBTITLE": @"移除應用程式中的廣告及促銷內容",
        @"DISABLE_ALL_ADS_TITLE": @"停用所有廣告",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"隱藏你正在選擇聯絡人的狀態",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"停用選擇聯絡人",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"隱藏你正在選擇位置的狀態",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"停用選擇位置狀態",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"隱藏你正在挑選貼圖的狀態",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"停用選擇貼圖狀態",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"隱藏你使用表情符號回應訊息的狀態",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"停用表情符號回應狀態",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"隱藏你與表情符號互動的狀態",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"停用表情符號互動狀態",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"防止他人看到你已閱讀他們的訊息",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"停用訊息已讀通知",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"防止他人看到你正在線上",
        @"DISABLE_ONLINE_STATUS_TITLE": @"停用在線狀態",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"隱藏你正在玩遊戲的狀態",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"停用遊戲狀態",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"隱藏你正在錄製圓形影片的狀態",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"停用錄製圓形影片狀態",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"隱藏你正在錄製影片的狀態",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"停用錄影狀態",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"隱藏你正在群組通話中說話的狀態",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"停用群組通話說話狀態",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"防止他人看到你已查看他們的動態",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"停用限時動態已讀通知",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"隱藏你正在輸入訊息的狀態",
        @"DISABLE_TYPING_STATUS_TITLE": @"停用輸入狀態",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"隱藏你正在上傳檔案的狀態",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"停用上傳檔案狀態",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"隱藏你正在上傳照片的狀態",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"停用上傳照片狀態",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"停用上傳圓形影片狀態",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"隱藏你正在上傳影片的狀態",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"停用上傳影片狀態",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"隱藏你正在錄製語音訊息的狀態",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"停用語音訊息錄製狀態",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"隱藏你正在上傳語音訊息的狀態",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"停用語音訊息上傳狀態",
        @"DISCLAIMER": @"免責聲明",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"允許你偽裝設備的GPS位置",
        @"ENABLE_FAKE_LOCATION_TITLE": @"啟用虛擬定位",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"繞過儲存受保護內容的限制",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"允許儲存受保護內容",
        @"FAKE_LOCATION_SECTION_HEADER": @"虛擬定位",
        @"FILE_FIXER_SECTION_HEADER": @"檔案選擇器修復",
        @"FIX_FILE_PICKER_SUBTITLE": @"修復側載版本無法從檔案應用程式選擇檔案的問題",
        @"FIX_FILE_PICKER_TITLE": @"修復檔案選擇器",
        @"GHOST_MODE_SECTION_HEADER": @"隱身模式",
        @"LANGUAGE_SECTION_HEADER": @"語言",
        @"MISC": @"其它",
        @"MISC_SECTION_HEADER": @"其它",
        @"OK": @"確定",
        @"READ_RECEIPTS": @"已讀通知",
        @"READ_RECEIPT_SECTION_HEADER": @"已讀通知",
        @"SELECT_FAKE_LOCATION_TITLE": @"選擇位置",
    };
    // vn: 65 keys
    NSDictionary *dict_vn = @{
        @"APPLY": @"Áp dụng",
        @"APPLY_CHANGES": @"Bạn có chắc muốn áp dụng các thay đổi này?",
        @"AUTHOR_MESSAGE": @"Bản chỉnh sửa Telegram này chỉ dành cho mục đích cá nhân và giáo dục. Chúng tôi không liên kết với Telegram. Mọi nhãn hiệu, bao gồm tên và logo Telegram, thuộc về chủ sở hữu tương ứng. Không sử dụng để vi phạm quy tắc, hành vi mờ ám hoặc điều khoản Telegram - chúng tôi không chịu trách nhiệm nếu có vấn đề phát sinh. Tự chịu rủi ro khi sử dụng. \n \nNếu bạn thích, hãy nói gì đó. Tôi thực sự sống nhờ sự công nhận. \n \nNếu muốn hỗ trợ tôi bằng cách quyên góp, hãy liên hệ với tôi trên Telegram",
        @"CACHE_CLEAR_WARNING_MESSAGE": @"Bạn có chắc chắn?",
        @"CACHE_CLEAR_WARNING_TITLE": @"Xác nhận",
        @"CANCEL": @"Hủy",
        @"CLEAR_FILE_PICKER_CACHE_SUBTITLE": @"Vì File Picker sao chép tệp vào thư mục tạm, cần xóa thủ công",
        @"CLEAR_FILE_PICKER_CACHE_TITLE": @"Xóa bộ nhớ đệm chọn tệp",
        @"CREDITS_SECTION_HEADER": @"Ghi công",
        @"DISABLE_ALL_ADS_SUBTITLE": @"Loại bỏ nội dung quảng cáo khỏi ứng dụng.",
        @"DISABLE_ALL_ADS_TITLE": @"Chặn tất cả quảng cáo",
        @"DISABLE_CHOOSING_CONTACT_SUBTITLE": @"Ẩn khi bạn đang chọn liên hệ.",
        @"DISABLE_CHOOSING_CONTACT_TITLE": @"Tắt trạng thái đang chọn liên hệ",
        @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE": @"Ẩn khi bạn đang chọn vị trí.",
        @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE": @"Tắt trạng thái đang chọn vị trí",
        @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE": @"Ẩn khi bạn đang chọn nhãn dán.",
        @"DISABLE_CHOOSING_STICKER_STATUS_TITLE": @"Tắt trạng thái đang chọn nhãn dán",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE": @"Ẩn khi bạn dùng emoji phản ứng tin nhắn.",
        @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE": @"Tắt trạng thái phản ứng emoji",
        @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE": @"Ẩn khi bạn tương tác bằng emoji.",
        @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE": @"Tắt trạng thái tương tác emoji",
        @"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE": @"Ngăn người khác thấy bạn đã đọc tin nhắn của họ.",
        @"DISABLE_MESSAGE_READ_RECEIPT_TITLE": @"Tắt trạng thái đã đọc tin nhắn",
        @"DISABLE_ONLINE_STATUS_SUBTITLE": @"Ngăn người khác thấy bạn đang online.",
        @"DISABLE_ONLINE_STATUS_TITLE": @"Tắt trạng thái online",
        @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE": @"Ẩn khi bạn đang chơi trò chơi.",
        @"DISABLE_PLAYING_GAME_STATUS_TITLE": @"Tắt trạng thái đang chơi game",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE": @"Ẩn khi bạn đang quay video tròn.",
        @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE": @"Tắt trạng thái đang quay video tròn",
        @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE": @"Ẩn khi bạn đang quay video.",
        @"DISABLE_RECORDING_VIDEO_STATUS_TITLE": @"Tắt trạng thái đang quay video",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE": @"Ẩn khi bạn đang nói trong cuộc gọi nhóm.",
        @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE": @"Tắt trạng thái đang nói trong cuộc gọi nhóm",
        @"DISABLE_STORY_READ_RECEIPT_SUBTITLE": @"Ngăn người khác thấy bạn đã xem story của họ.",
        @"DISABLE_STORY_READ_RECEIPT_TITLE": @"Tắt trạng thái đã xem story",
        @"DISABLE_TYPING_STATUS_SUBTITLE": @"Ẩn khi bạn đang soạn tin nhắn.",
        @"DISABLE_TYPING_STATUS_TITLE": @"Tắt trạng thái đang nhập",
        @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE": @"Ẩn khi bạn đang tải tệp lên.",
        @"DISABLE_UPLOADING_FILE_STATUS_TITLE": @"Tắt trạng thái đang tải tệp lên",
        @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE": @"Ẩn khi bạn đang tải ảnh lên",
        @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE": @"Tắt trạng thái đang tải ảnh lên",
        @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE": @"Tắt trạng thái đang tải video tròn lên",
        @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE": @"Ẩn khi bạn đang tải video lên",
        @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE": @"Tắt trạng thái đang tải lên video",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE": @"Ẩn khi bạn đang ghi âm tin nhắn.",
        @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE": @"Tắt trạng thái đang ghi âm",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE": @"Ẩn khi bạn đang tải tin nhắn thoại lên.",
        @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE": @"Tắt trạng thái đang tải lên tin nhắn thoại",
        @"DISCLAIMER": @"Tuyên bố miễn trừ",
        @"ENABLE_FAKE_LOCATION_SUBTITLE": @"Cho phép giả mạo vị trí GPS của thiết bị",
        @"ENABLE_FAKE_LOCATION_TITLE": @"Bật giả mạo vị trí",
        @"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE": @"Cho phép lưu và chụp ảnh màn hình nội dung được bảo vệ.",
        @"ENABLE_SAVING_PROTECTED_CONTENT_TITLE": @"Cho phép lưu nội dung được bảo vệ",
        @"FAKE_LOCATION_SECTION_HEADER": @"Vị trí giả",
        @"FILE_FIXER_SECTION_HEADER": @"Sửa lỗi chọn tệp",
        @"FIX_FILE_PICKER_SUBTITLE": @"Khắc phục lỗi không thể chọn tệp từ ứng dụng Files trên bản sideload",
        @"FIX_FILE_PICKER_TITLE": @"Sửa lỗi chọn tệp",
        @"GHOST_MODE_SECTION_HEADER": @"Chế độ ma",
        @"LANGUAGE_SECTION_HEADER": @"Ngôn ngữ",
        @"MISC": @"Khác",
        @"MISC_SECTION_HEADER": @"Khác",
        @"OK": @"Đồng ý",
        @"READ_RECEIPTS": @"Trạng thái đã đọc",
        @"READ_RECEIPT_SECTION_HEADER": @"Trạng thái đã đọc",
        @"SELECT_FAKE_LOCATION_TITLE": @"Chọn vị trí",
    };

        NSMutableDictionary *allTranslations = [NSMutableDictionary dictionary];
        [allTranslations setObject:dict_ar forKey:@"ar"];
        [allTranslations setObject:dict_cn forKey:@"cn"];
        [allTranslations setObject:dict_en forKey:@"en"];
        [allTranslations setObject:dict_fr forKey:@"fr"];
        [allTranslations setObject:dict_it forKey:@"it"];
        [allTranslations setObject:dict_ja forKey:@"ja"];
        [allTranslations setObject:dict_ru forKey:@"ru"];
        [allTranslations setObject:dict_es forKey:@"es"];
        [allTranslations setObject:dict_tw forKey:@"tw"];
        [allTranslations setObject:dict_vn forKey:@"vn"];
        TGXAllTranslations = [allTranslations copy];

        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"TGExtraLanguage"];
        TGXCurrentLang = (saved && TGXAllTranslations[saved]) ? saved : @"en";
    });
}

static NSDictionary *TGXDictForLang(NSString *code) {
    NSDictionary *d = TGXAllTranslations[code];
    return d ? d : TGXAllTranslations[@"en"];
}

// ==========================================================================
// Swizzled +[TGExtraLocalization localizedStringForKey:]
// ==========================================================================

static NSString *TGX_LocalizedStringForKey(id self, SEL _cmd, NSString *key) {
    TGXLoadTranslations();
    if (!key) return nil;
    NSDictionary *d = TGXDictForLang(TGXCurrentLang);
    NSString *v = d[key];
    if (v) return v;
    NSDictionary *en = TGXAllTranslations[@"en"];
    return en[key] ? en[key] : key;
}

// ==========================================================================
// Swizzled -[LanguageSelector viewDidLoad]
// Populate self.languages with the full embedded list (so all 10 languages are
// selectable) and seed the active localization, then fall through to original.
// ==========================================================================

static void (*TGX_OrigLanguageSelectorViewDidLoad)(id, SEL);

static void TGX_LanguageSelectorViewDidLoad(id self, SEL _cmd) {
    NSArray *langs = @[
        @{@"name": @"Arabic", @"code": @"ar", @"flag": @"🇸🇦"},
        @{@"name": @"Chinese", @"code": @"cn", @"flag": @"🇨🇳"},
        @{@"name": @"English", @"code": @"en", @"flag": @"🇺🇸"},
        @{@"name": @"French", @"code": @"fr", @"flag": @"🇫🇷"},
        @{@"name": @"Italian", @"code": @"it", @"flag": @"🇮🇹"},
        @{@"name": @"Japanese", @"code": @"ja", @"flag": @"🇯🇵"},
        @{@"name": @"Russian", @"code": @"ru", @"flag": @"🇷🇺"},
        @{@"name": @"Spanish", @"code": @"es", @"flag": @"🇪🇸"},
        @{@"name": @"Taiwan", @"code": @"tw", @"flag": @"🇹🇼"},
        @{@"name": @"Vietnamese", @"code": @"vn", @"flag": @"🇻🇳"},
    ];
    @try {
        [self setValue:langs forKey:@"languages"];
    } @catch (NSException *e) {
        NSLog(@"[TGExtraResources] failed to set languages: %@", e);
    }

    TGXLoadTranslations();
    NSString *code = TGXCurrentLang;
    NSDictionary *dict = TGXDictForLang(code);
    Class TGExtraLocalization = objc_getClass("TGExtraLocalization");
    if (TGExtraLocalization && dict) {
        TGLocalization *loc = [[objc_getClass("TGLocalization") alloc] initWithVersion:96929692
                                                                                  code:code
                                                                                  dict:dict
                                                                              isActive:YES];
        if (loc) {
            @try { [[TGExtraLocalization shared] setValue:loc forKey:@"localization"]; }
            @catch (NSException *e) { NSLog(@"[TGExtraResources] seed loc failed: %@", e); }
        }
    }

    if (TGX_OrigLanguageSelectorViewDidLoad) {
        TGX_OrigLanguageSelectorViewDidLoad(self, _cmd);
    }
}

// ==========================================================================
// Swizzled -[LanguageSelector tableView:didSelectRowAtIndexPath:]
// ==========================================================================

static void TGX_LanguageSelectorDidSelect(id self, SEL _cmd, id tableView, NSIndexPath *indexPath) {
    NSArray *langs = nil;
    @try { langs = [self valueForKey:@"languages"]; } @catch (NSException *e) { return; }
    if (!langs || indexPath.row >= (NSInteger)langs.count) return;
    NSDictionary *languageData = langs[indexPath.row];
    NSString *code = languageData[@"code"];
    NSDictionary *dict = TGXDictForLang(code);
    if (!dict) return;

    TGXCurrentLang = code;
    [[NSUserDefaults standardUserDefaults] setObject:code forKey:@"TGExtraLanguage"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    Class TGExtraLocalization = objc_getClass("TGExtraLocalization");
    TGLocalization *loc = [[objc_getClass("TGLocalization") alloc] initWithVersion:96929692
                                                                              code:code
                                                                              dict:dict
                                                                          isActive:YES];
    if (loc && TGExtraLocalization) {
        @try { [[TGExtraLocalization shared] setValue:loc forKey:@"localization"]; }
        @catch (NSException *e) { NSLog(@"[TGExtraResources] didSelect loc failed: %@", e); }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"LanguageChangedNotification" object:nil];
    [(UITableView *)tableView deselectRowAtIndexPath:indexPath animated:YES];
    [(UITableView *)tableView reloadData];
}

// ==========================================================================
// Install hooks once TGExtra's classes exist
// ==========================================================================

static void TGXSetup(void) {
    TGXLoadTranslations();

    Class TGExtraLocalization = objc_getClass("TGExtraLocalization");
    if (!TGExtraLocalization) {
        NSLog(@"[TGExtraResources] TGExtraLocalization class not found yet");
        return;
    }

    // 1) Swizzle +[TGExtraLocalization localizedStringForKey:] on the metaclass.
    {
        Class meta = object_getClass(TGExtraLocalization);
        Method orig = class_getClassMethod(TGExtraLocalization,
                                           NSSelectorFromString(@"localizedStringForKey:"));
        if (orig) {
            method_setImplementation(orig, (IMP)TGX_LocalizedStringForKey);
            NSLog(@"[TGExtraResources] swizzled +localizedStringForKey:");
        } else {
            class_addMethod(meta, NSSelectorFromString(@"localizedStringForKey:"),
                            (IMP)TGX_LocalizedStringForKey, "@@:@@:");
        }
    }

    // 2) Pre-seed the localization so the default language renders immediately.
    {
        NSString *code = TGXCurrentLang;
        NSDictionary *dict = TGXDictForLang(code);
        TGLocalization *loc = [[objc_getClass("TGLocalization") alloc] initWithVersion:96929692
                                                                                  code:code
                                                                                  dict:dict
                                                                              isActive:YES];
        if (loc) {
            id shared = [TGExtraLocalization shared];
            if (shared) {
                @try { [shared setValue:loc forKey:@"localization"]; }
                @catch (NSException *e) {}
            }
        }
    }

    // 3) Swizzle LanguageSelector.
    Class LanguageSelector = objc_getClass("LanguageSelector");
    if (LanguageSelector) {
        Method m = class_getInstanceMethod(LanguageSelector, NSSelectorFromString(@"viewDidLoad"));
        if (m) {
            TGX_OrigLanguageSelectorViewDidLoad = (void (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)TGX_LanguageSelectorViewDidLoad);
            NSLog(@"[TGExtraResources] swizzled -[LanguageSelector viewDidLoad]");
        }
        Method m2 = class_getInstanceMethod(LanguageSelector,
                                            NSSelectorFromString(@"tableView:didSelectRowAtIndexPath:"));
        if (m2) {
            method_setImplementation(m2, (IMP)TGX_LanguageSelectorDidSelect);
            NSLog(@"[TGExtraResources] swizzled -[LanguageSelector tableView:didSelectRowAtIndexPath:]");
        }
    }

    NSLog(@"[TGExtraResources] shim installed (lang=%@, %lu langs, %lu keys/en)",
          TGXCurrentLang, (unsigned long)TGXAllTranslations.count,
          (unsigned long)TGXAllTranslations[@"en"].count);
}

static void TGXSetupRetry(int attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        TGXSetup();
        if (!objc_getClass("TGExtraLocalization") && attempt < 8) {
            TGXSetupRetry(attempt + 1);
        }
    });
}

__attribute__((constructor))
static void TGXEntry(void) {
    NSLog(@"[TGExtraResources] constructor fired");
    TGXSetupRetry(0);
}
