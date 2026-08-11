#!/usr/bin/env python3
"""Apply the iOS 15.0 compatibility call-site rewrites.

iOS 16+ API call sites across the app are rewritten to the shims in
`TiebaPure/Core/UI/Compatibility.swift`. Every rule is idempotent — running
the script on already patched sources is a no-op — so the GitHub Actions
workflows can run it after every checkout and commit the result back to the
branch.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_ROOT = ROOT / "TiebaPure"
TEST_ROOT = ROOT / "TiebaPureTests"
COMPAT_FILE = APP_ROOT / "Core" / "UI" / "Compatibility.swift"

report = []
missing_count = 0


def note(message):
    report.append(message)


# ---------------------------------------------------------------------------
# Global mechanical renames applied to every app Swift source file.
# (label, pattern, replacement)
# ---------------------------------------------------------------------------
GLOBAL_RULES = [
    ("navigationDestination", r"\.navigationDestination\(", ".compatibleNavigationDestination("),
    ("toolbar(.visible, tabBar)", r"\.toolbar\(\s*\.visible\s*,\s*for:\s*\.tabBar\s*\)", ".compatibleTabBarVisibility(.visible)"),
    ("toolbar(.hidden, tabBar)", r"\.toolbar\(\s*\.hidden\s*,\s*for:\s*\.tabBar\s*\)", ".compatibleTabBarVisibility(.hidden)"),
    ("scrollContentBackground", r"\.scrollContentBackground\(\s*\.hidden\s*\)", ".compatibleScrollContentBackgroundHidden()"),
    ("scrollDismissesKeyboard", r"\.scrollDismissesKeyboard\(\s*\.interactively\s*\)", ".compatibleScrollDismissesKeyboardInteractively()"),
    ("scrollBounceBehavior", r"\.scrollBounceBehavior\([^)]*\)", ".compatibleScrollBounceBehaviorAlwaysVertical()"),
    ("scrollIndicators", r"\.scrollIndicators\(\s*\.hidden\s*\)", ".compatibleScrollIndicatorsHidden()"),
    ("fontDesign", r"\.fontDesign\(\s*\.monospaced\s*\)", ".compatibleFontDesign(.monospaced)"),
    ("URL.appending(path:)", r"\.appending\(\s*path:", ".compatAppending(path:"),
    ("URL.appending(queryItems:)", r"\.appending\(\s*queryItems:", ".compatAppending(queryItems:"),
    ("ViewThatFits", r"\bViewThatFits\(", "CompatibleViewThatFits("),
    ("LabeledContent", r"\bLabeledContent\(", "CompatibleLabeledContent("),
    ("NavigationStack(path:)", r"\bNavigationStack\(\s*path:", "CompatiblePathNavigationStack(path:"),
    ("NavigationStack", r"\bNavigationStack\s*\{", "CompatibleNavigationStack {"),
    ("ShareLink", r"\bShareLink\(\s*item:", "CompatibleShareLink(item:"),
]


def apply_global_rules(rel, text):
    for label, pattern, replacement in GLOBAL_RULES:
        text, count = re.subn(pattern, replacement, text)
        if count:
            note("  applied %s: %s x%d" % (rel, label, count))
    return text


# ---------------------------------------------------------------------------
# File-specific rules.
#   ("exact", old, new, label)                    — literal replace-all
#   ("regex", pattern, replacement, marker, label) — marker only for status
#   ("sizeThatFits",)                              — prepend @available(iOS 16)
# ---------------------------------------------------------------------------
PRESENTATION_DETENTS_OLD = (
    "        } else {\n"
    "            presentationDetents([.large])\n"
    "                .presentationDragIndicator(.hidden)\n"
    "                .interactiveDismissDisabled()\n"
    "        }"
)
PRESENTATION_DETENTS_NEW = (
    "        } else if #available(iOS 16.0, *) {\n"
    "            presentationDetents([.large])\n"
    "                .presentationDragIndicator(.hidden)\n"
    "                .interactiveDismissDisabled()\n"
    "        } else {\n"
    "            interactiveDismissDisabled()\n"
    "        }"
)

FILE_RULES = {
    "TiebaPure/Core/State/ForumSignCoordinator.swift": [
        ("exact",
         "private let requestSpacing: Duration",
         "private let requestSpacing: TimeInterval",
         "requestSpacing property type"),
        ("exact",
         "requestSpacing: Duration = .milliseconds(350)",
         "requestSpacing: TimeInterval = 0.35",
         "requestSpacing default value"),
        ("exact",
         "try await Task.sleep(for: requestSpacing)",
         "try await Task.compatSleep(seconds: requestSpacing)",
         "request spacing sleep"),
    ],
    "TiebaPure/Core/UI/ShortPullRefresh.swift": [
        ("exact",
         "try await Task.sleep(for: .milliseconds(650))",
         "try await Task.compatSleep(seconds: 0.65)",
         "scroll probe idle sleep"),
    ],
    "TiebaPure/Core/UI/CompatibleUnavailableView.swift": [
        ("exact",
         ".font(.system(.largeTitle, design: .rounded, weight: .regular))",
         ".font(.compatSystem(.largeTitle, design: .rounded, weight: .regular))",
         "largeTitle icon font"),
    ],
    "TiebaPure/Core/UI/ReaderSplitLayout.swift": [
        ("exact",
         "        if horizontalSizeClass == .regular {",
         "        if #available(iOS 16.0, *), horizontalSizeClass == .regular {",
         "split layout availability gate"),
        ("exact",
         "    private func splitNavigation(leadingColumnWidth: CGFloat) -> some View {",
         "    @available(iOS 16.0, *)\n    private func splitNavigation(leadingColumnWidth: CGFloat) -> some View {",
         "splitNavigation availability"),
        ("exact",
         "    @ViewBuilder\n    private func splitListNavigation(leadingColumnWidth: CGFloat) -> some View {",
         "    @available(iOS 16.0, *)\n    @ViewBuilder\n    private func splitListNavigation(leadingColumnWidth: CGFloat) -> some View {",
         "splitListNavigation availability"),
    ],
    "TiebaPure/Features/Thread/ThreadDetailView.swift": [
        ("exact",
         "static let idleDelay: Duration = .milliseconds(250)",
         "static let idleDelay: TimeInterval = 0.25",
         "reading persistence idle delay"),
        ("exact",
         "Task.sleep(for: .milliseconds(1_500))",
         "Task.compatSleep(seconds: 1.5)",
         "initial scroll request sleep"),
        ("exact",
         "Task.sleep(for: ThreadReadingPersistencePolicy.idleDelay)",
         "Task.compatSleep(seconds: ThreadReadingPersistencePolicy.idleDelay)",
         "reading persistence sleep"),
        ("exact",
         PRESENTATION_DETENTS_OLD,
         PRESENTATION_DETENTS_NEW,
         "subpost sheet iOS 15 fallback"),
    ],
    "TiebaPure/Features/Compose/ContentComposerView.swift": [
        ("exact",
         "[PhotosPickerItem]",
         "[CompatiblePhotoItem]",
         "photo selection item type"),
        ("regex",
         r"\bPhotosPicker\(\s*selection:\s*\$photoSelection,\s*maxSelectionCount:\s*remaining,\s*matching:\s*\.images,\s*preferredItemEncoding:\s*\.current\s*\)",
         "CompatiblePhotosPicker(\n                        selection: $photoSelection,\n                        maxSelectionCount: remaining\n                    )",
         "CompatiblePhotosPicker(",
         "photos picker presentation"),
        ("regex",
         r'\bTextField\("请输入帖子标题",\s*text:\s*\$title,\s*axis:\s*\.vertical\)',
         'CompatibleVerticalTextField("请输入帖子标题", text: $title, lineLimit: 1...3)',
         "CompatibleVerticalTextField(",
         "vertical title field"),
        ("regex",
         r"\n[ \t]*\.lineLimit\(1\.\.\.3\)",
         "",
         "CompatibleVerticalTextField(",
         "title field lineLimit chain"),
        ("regex",
         r"\.loadTransferable\(\s*type:\s*Data\.self\s*\)",
         ".loadImageData()",
         ".loadImageData()",
         "photo data loading"),
    ],
    "TiebaPure/Features/Media/ImageViewer.swift": [
        ("sizeThatFits",),
    ],
    "TiebaPure/Features/Thread/ContentBlockView.swift": [
        ("sizeThatFits",),
    ],
}

# The test bundle is built with a 17.0 deployment target (see project.yml), so
# only app-API signature changes need patching here, not API availability.
TEST_FILE_RULES = {
    "TiebaPureTests/ForumSignTests.swift": [
        ("exact",
         "requestSpacing: .milliseconds(500)",
         "requestSpacing: 0.5",
         "requestSpacing seconds in tests"),
    ],
}

SIZE_THAT_FITS = re.compile(
    r"(?m)^(?P<indent>[ \t]*)func sizeThatFits\(\s*\n\s*_ proposal: ProposedViewSize,"
)


def apply_exact(text, old, new):
    if new in text:
        return text, "already"
    if old in text:
        return text.replace(old, new), "applied"
    return text, "missing"


def apply_regex(text, pattern, replacement, marker):
    new_text, count = re.subn(pattern, replacement, text)
    if count:
        return new_text, "applied"
    if marker in text:
        return text, "already"
    return text, "missing"


def apply_size_that_fits(text):
    matches = list(SIZE_THAT_FITS.finditer(text))
    if not matches:
        return text, "missing"
    changed = False
    for match in reversed(matches):
        prefix = text[max(0, match.start() - 64):match.start()]
        if "@available" in prefix:
            continue
        indent = match.group("indent")
        replacement = (
            indent + "@available(iOS 16.0, *)\n"
            + indent + "func sizeThatFits(\n"
            + indent + "    _ proposal: ProposedViewSize,"
        )
        text = text[:match.start()] + replacement + text[match.end():]
        changed = True
    return text, ("applied" if changed else "already")


def process_file(path, rules, use_globals):
    global missing_count
    rel = path.relative_to(ROOT).as_posix()
    original = path.read_text(encoding="utf-8")
    text = apply_global_rules(rel, original) if use_globals else original

    for rule in rules:
        if rule[0] == "exact":
            _, old, new, label = rule
            text, status = apply_exact(text, old, new)
        elif rule[0] == "regex":
            _, pattern, replacement, marker, label = rule
            text, status = apply_regex(text, pattern, replacement, marker)
        elif rule[0] == "sizeThatFits":
            label = "sizeThatFits availability"
            text, status = apply_size_that_fits(text)
        else:
            continue
        note("  [%s] %s: %s" % (status, rel, label))
        if status == "missing":
            missing_count += 1

    if text != original:
        path.write_text(text, encoding="utf-8")
    return rel, text != original


def main():
    if not APP_ROOT.is_dir():
        print("app sources not found at %s" % APP_ROOT, file=sys.stderr)
        return 1

    patched_files = []

    for path in sorted(APP_ROOT.rglob("*.swift")):
        if path == COMPAT_FILE:
            continue
        rel = path.relative_to(ROOT).as_posix()
        _, changed = process_file(path, FILE_RULES.get(rel, []), True)
        if changed:
            patched_files.append(rel)

    if TEST_ROOT.is_dir():
        for path in sorted(TEST_ROOT.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            rules = TEST_FILE_RULES.get(rel)
            if not rules:
                continue
            _, changed = process_file(path, rules, False)
            if changed:
                patched_files.append(rel)

    print("iOS 15 compatibility patch report")
    print("=================================")
    for line in report:
        print(line)
    print()
    if patched_files:
        print("Patched %d files:" % len(patched_files))
        for rel in patched_files:
            print("  " + rel)
    else:
        print("All sources already patched.")
    if missing_count:
        print("MISSING rules: %d (source drifted - needs a manual look)" % missing_count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
