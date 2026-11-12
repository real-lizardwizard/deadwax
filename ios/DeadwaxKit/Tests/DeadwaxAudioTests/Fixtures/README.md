What DeadwaxAudio's tests read. Never edit by hand.

- `verifier/` - the downloaded-copy verifier's FLACs (DownloadedCopyTests): 16-bit 44.1 kHz and 24-bit 96 kHz with
  their MD5s, the 24-bit one with one sample changed after hashing (every frame's CRC still right), and a 16-bit one
  with no MD5. Written by `python3 ios/scripts/make-test-album.py --verifier-fixtures <this folder>/verifier`, the
  same encoder as the test album's; `tests/test_ios_install.py` checks the files are the script's and that libsndfile
  hears what their MD5s say.
