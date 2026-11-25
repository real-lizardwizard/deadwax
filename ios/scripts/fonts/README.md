# The app's fonts, as downloaded

The iPhone and Mac app's two faces, chosen by James on 25 Nov 2026 ("libre franklin", then "Adopt it"): **Libre
Franklin** for words and **Courier Prime** for readouts. `ios/scripts/make-fonts.py` makes `ios/App/Fonts` from
these files and nothing else - nothing is fetched when it runs. notes/ios.md, "The app's fonts: Libre Franklin and
Courier Prime (2026-11-25)", has the rest.

Downloaded once, with James's OK, from Google Fonts' repository, github.com/google/fonts, at commit
`6ebe737e44fd64ee736bbc6feed6136a6dbfd222` (`ofl/librefranklin` and `ofl/courierprime`). Each is under the SIL Open
Font License 1.1, its own `OFL.txt` beside it with its own copyright line.

| file | bytes | sha256 |
| --- | --- | --- |
| librefranklin/LibreFranklin[wght].ttf | 187436 | 2329f394b10ed1c71107df20fddc11e2bb1b68c1ecbb385f975b36fd64a971f8 |
| librefranklin/OFL.txt | 4495 | 2710268527181a27b8e938617551bae29e714e6525247be6679bf897a9942a60 |
| courierprime/CourierPrime-Regular.ttf | 71188 | 72f793376f8e2841656bf21d77a5de010f2929bd6956a22ee848ad0c7eb978af |
| courierprime/CourierPrime-Bold.ttf | 72856 | ff1f38786c849d1c41fa8e447960abdb2bd75fdfb0cfcdeb524fad65a5af3638 |
| courierprime/OFL.txt | 4403 | 9a755af092b494944c99f471be6fddd19b006a448fefdc4717e4ee0aa09a97b0 |

Libre Franklin's OFL.txt has Windows line endings, as downloaded; it is kept byte for byte. tests/test_ios_palette.py
holds every file here to its hash.

The faces in `ios/App/Fonts` were made with **fontTools 4.68.0** (`pip install fonttools==4.68.0`, in the venv
make-fonts.py's docstring names): run again with that version, make-fonts.py writes them byte for byte. Another
version's instancer may write other bytes.
