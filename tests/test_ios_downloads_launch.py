"""The iPhone app's launch kept off the disk (23 Nov, notes/ios.md "A slow start, and the watchdog").

A Time Profiler trace of a launch on James's iPhone showed the main thread busy for about four seconds before the
first frame, most of it in `lstat`: DownloadModel.reload() built every downloaded song's file URL with
`appendingPathComponent(_:)`, which - with no hint - asks the disk whether the name is a folder; settle() asked every
song's file for its attributes each time the app came to the front; and the planner read the volume's free space at
every plan. iOS's watchdog killed the app (0x8BADF00D) when that kept the main thread from a scene update in time.

These read the Swift: a song's, a part's and a cover's URL say they are files; settle() lists the music folder once;
the planner's free space is kept a while (Core's KeptFreeSpace, tested on Linux).
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOWNLOADS = REPO / "ios" / "App" / "Downloads"
STORE = (DOWNLOADS / "DownloadStore.swift").read_text(encoding="utf-8")
MODEL = (DOWNLOADS / "DownloadModel.swift").read_text(encoding="utf-8")
CORE = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "KeptFreeSpace.swift").read_text(encoding="utf-8")


def body(source: str, signature: str) -> str:
    """The text of the function whose declaration starts with `signature`, to its closing brace."""
    start = source.index(signature)
    depth = 0
    for i in range(source.index("{", start), len(source)):
        depth += {"{": 1, "}": -1}.get(source[i], 0)
        if depth == 0:
            return source[start:i + 1]
    raise AssertionError(f"{signature}: no end")


def test_a_songs_a_parts_and_a_covers_url_say_they_are_files():
    assert "music.appendingPathComponent($0, isDirectory: false)" in body(STORE, "func fileURL(")
    assert 'music.appendingPathComponent($0 + ".part", isDirectory: false)' in body(STORE, "func partURL(_ record")
    assert '.appendingPathComponent(file + ".part", isDirectory: false)' in body(STORE, "static func partURL(for")
    assert "covers.appendingPathComponent(name, isDirectory: false)" in body(STORE, "func coverURL(")
    # every cover's URL in the model is the store's
    assert "covers.appendingPathComponent" not in MODEL
    assert MODEL.count("store.coverURL(") == 4


def test_reload_asks_the_disk_nothing_per_song():
    reload = body(MODEL, "private func reload()")
    assert "store.fileURL(record)" in reload
    assert "appendingPathComponent" not in reload
    assert "FileManager" not in reload and "DownloadStore.length" not in reload
    # a cover's length is read once (coverLength keeps it)
    assert "coverLength(" in reload


def test_settle_lists_the_music_folder_once():
    settle = body(MODEL, "private func settle(_ opened: DownloadStore) async")
    assert settle.count("contentsOfDirectory(") == 1
    assert "let listed = try? FileManager.default.contentsOfDirectory(atPath: opened.music.path)" in settle
    assert "let present = listed.map(Set.init)" in settle
    # a done song is missing when the listing lacks its name; only an unread folder (or a name with a folder in it)
    # asks the file itself
    assert ('present.flatMap({ name.contains("/") ? nil : !$0.contains(name) }) ?? (DownloadStore.length(url) == nil)'
            in settle)
    assert settle.count("DownloadStore.length(") == 1
    # the .part sweep and the unnamed files read the same listing
    assert "let parts = (listed ?? []).map { opened.music.appendingPathComponent($0, isDirectory: false) }" in settle


def test_the_planners_free_space_is_kept_a_while():
    plan = body(MODEL, "private func plan()")
    assert "DownloadStore.plannersFreeSpace(used: bytesHere)" in plan
    assert "DownloadStore.freeSpace()" not in MODEL
    keeper = body(STORE, "@MainActor static func plannersFreeSpace(used: Int64)")
    assert "ProcessInfo.processInfo.systemUptime" in keeper
    assert "keptFreeSpace?.estimate(now: now, used: used)" in keeper
    assert "KeptFreeSpace(bytes: $0, at: now, used: used)" in keeper
    assert re.search(r"public static let keptFor: Double = 30\n", CORE)
