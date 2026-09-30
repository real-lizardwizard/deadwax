"""
Tag names mutagen's easy interfaces don't know, taught to them once for the whole process.

Easy ID3 already maps `discsubtitle` to TSST and Vorbis comments take any name, but Easy MP4 has
no key for it, so an m4a's disc title could be neither read (the scan, the track viewer) nor
written (a download, an apply, a hand edit - each would skip it as a tag the format can't hold).
It is registered as the freeform atom Picard writes and Navidrome reads,
`----:com.apple.iTunes:DISCSUBTITLE` (v1.1.0).

Registration changes mutagen's class for everyone, so the files that read or write these keys are
opened through easy_file(), which makes sure it has happened first.
"""

#? easy key -> the freeform atom's name, under com.apple.iTunes
MP4_FREEFORM_KEYS = {
    "discsubtitle": "DISCSUBTITLE",
}

_registered = False


def easy_file(path):
    """mutagen.File(path, easy=True), with the keys above known to Easy MP4."""
    global _registered
    import mutagen

    if not _registered:
        from mutagen.easymp4 import EasyMP4Tags
        for key, name in MP4_FREEFORM_KEYS.items():
            EasyMP4Tags.RegisterFreeformKey(key, name)
        _registered = True

    return mutagen.File(str(path), easy=True)
