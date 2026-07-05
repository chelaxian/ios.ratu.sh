#!/usr/bin/env python3
"""
Generate TGExtraResources shim source (ObjC++) with all 10 languages embedded
as NSDictionary literals, plus swizzle logic for:
  - +[TGExtraLocalization localizedStringForKey:]  (the single TGLoc() funnel)
  - -[LanguageSelector viewDidLoad]                 (populate language list)
  - -[LanguageSelector tableView:didSelectRowAtIndexPath:]

Reads TGExtra.bundle/<lang>.lproj/Localizable.strings and langs.json from the
cloned waruhachi/TGExtra repo, emits a self-contained .m file.

Avoids f-strings for the ObjC body (too many literal braces); uses str.replace
on a plain string template instead.
"""
import json
import re
import sys
from pathlib import Path

BUNDLE_DIR = Path(r"C:\Users\r_ratush\ZCodeProject\TGExtra\TGExtra.bundle")
OUT_SRC = Path(r"C:\Users\r_ratush\ZCodeProject\ios.ratu.sh\_tgx_shim_src\TGExtraResources.m")
OUT_SRC.parent.mkdir(parents=True, exist_ok=True)

LANGS = json.loads((BUNDLE_DIR / "langs.json").read_text(encoding="utf-8"))
LANG_CODES = [l["code"] for l in LANGS]

STRING_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')

def unescape_ns(s: str) -> str:
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            nxt = s[i+1]
            if nxt == 'n': out.append('\n')
            elif nxt == 't': out.append('\t')
            elif nxt == '"': out.append('"')
            elif nxt == '\\': out.append('\\')
            else: out.append(nxt)
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)

def parse_strings(path: Path) -> dict:
    d = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = STRING_RE.match(line)
        if m:
            d[m.group(1)] = m.group(2)
    return d

translations = {}
for code in LANG_CODES:
    p = BUNDLE_DIR / f"{code}.lproj" / "Localizable.strings"
    translations[code] = parse_strings(p)

en_keys = set(translations["en"].keys())
for code in LANG_CODES:
    missing = en_keys - set(translations[code].keys())
    if missing:
        print(f"WARN: {code} missing {len(missing)} keys: {sorted(missing)[:5]}", file=sys.stderr)

def objc_escape(s: str) -> str:
    # s has already been unescaped from .strings format (real newlines etc).
    # Produce a safe ObjC @"..." literal body.
    out = []
    for ch in s:
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\t':
            out.append('\\t')
        elif ch == '\r':
            out.append('\\r')
        else:
            out.append(ch)
    return ''.join(out)

def emit_dict(code: str, d: dict) -> str:
    lines = [f'    // {code}: {len(d)} keys']
    lines.append('    NSDictionary *dict_%s = @{' % code)
    for k in sorted(d.keys()):
        # unescape_ns turns \n etc into real chars; objc_escape re-encodes for ObjC literal
        val = objc_escape(unescape_ns(d[k]))
        key = objc_escape(k)
        lines.append(f'        @"{key}": @"{val}",')
    lines.append('    };')
    return '\n'.join(lines)

all_dicts = '\n'.join(emit_dict(c, translations[c]) for c in LANG_CODES)
all_lang_keys_init = '\n'.join(
    '        [allTranslations setObject:dict_%s forKey:@"%s"];' % (c, c) for c in LANG_CODES
)
lang_entries = []
for l in LANGS:
    lang_entries.append(
        '        @{@"name": @"%s", @"code": @"%s", @"flag": @"%s"},'
        % (objc_escape(l["name"]), l["code"], l["flag"])
    )
lang_entries_str = '\n'.join(lang_entries)

print(f"Parsed {len(LANG_CODES)} languages, en has {len(en_keys)} keys", file=sys.stderr)

TEMPLATE = r'''// ==========================================================================
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
__ALL_DICTS__

        NSMutableDictionary *allTranslations = [NSMutableDictionary dictionary];
__ALL_LANG_KEYS_INIT__
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
__LANG_ENTRIES__
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
'''

src = (TEMPLATE
       .replace('__ALL_DICTS__', all_dicts)
       .replace('__ALL_LANG_KEYS_INIT__', all_lang_keys_init)
       .replace('__LANG_ENTRIES__', lang_entries_str))

OUT_SRC.write_text(src, encoding="utf-8")
print(f"Wrote {OUT_SRC} ({len(src)} bytes)", file=sys.stderr)
