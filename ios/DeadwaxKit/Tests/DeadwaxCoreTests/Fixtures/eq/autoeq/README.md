Real files from **AutoEq** (github.com/jaakkopasanen/AutoEq, by Jaakko Pasanen), fetched unchanged from
raw.githubusercontent.com at its commit 7ae0f56d53074872b028649617a22bbb4232feb7, under AutoEq's own paths. AutoEq is
MIT-licensed ("Copyright (c) 2018-2022 Jaakko Pasanen" - its LICENSE is beside this file), and the licence covers its
results. The measurements behind each result are its measurer's; AutoEq computed the corrections from them.

What the EQ's Core tests read them for (notes/ios-specs/eq.md, 5.1): ios/scripts/make-eq-fixtures.py reads each with its
own reader of Equalizer APO's rules and computes their curve with AutoEq's own biquads (profiles.json, graphic.json),
and DeadwaxCoreTests' AutoEqProfileTests and GraphicEQFitTests read the files themselves.

| file (under results/) | measured by | rig |
| --- | --- | --- |
| crinacle/711 in-ear/Apple AirPods Pro/ - ParametricEQ.txt, GraphicEQ.txt | crinacle | 711 (in-ear) |
| crinacle/711 in-ear/Apple AirPods Pro 2 (ANC mode)/ - ParametricEQ.txt | crinacle | 711 (in-ear) |
| crinacle/GRAS 43AG-7 over-ear/Sennheiser HD 650/ - ParametricEQ.txt | crinacle | GRAS 43AG-7 (over-ear) |
| oratory1990/over-ear/Sennheiser HD 650/ - ParametricEQ.txt, GraphicEQ.txt, FixedBandEQ.txt, the .csv | oratory1990 | over-ear |
| oratory1990/over-ear/Apple AirPods Max/ - ParametricEQ.txt, the .csv | oratory1990 | over-ear |
| oratory1990/in-ear/Etymotic ER2XR/ - ParametricEQ.txt | oratory1990 | in-ear |
| Super Review/in-ear/Apple AirPods Pro/ - ParametricEQ.txt | Super Review | in-ear |
| HypetheSonics/Bruel & Kjaer 5128 in-ear/Apple AirPods Pro/ - ParametricEQ.txt | HypetheSonics | Bruel & Kjaer 5128 (in-ear) |
| Rtings/HMS II.3 in-ear/Apple AirPods Pro/ - ParametricEQ.txt | Rtings | HMS II.3 (in-ear) |
| Rtings/Bruel & Kjaer 5128 over-ear/Beyerdynamic DT 770 Pro/ - ParametricEQ.txt | Rtings | Bruel & Kjaer 5128 (over-ear) |
| Innerfidelity/over-ear/Sennheiser HD 650/ - ParametricEQ.txt | Innerfidelity | over-ear |
| Headphone.com Legacy/over-ear/Sennheiser HD 650/ - ParametricEQ.txt | Headphone.com Legacy | over-ear |
| Kuulokenurkka/over-ear/Sennheiser HD 6XX/ - ParametricEQ.txt | Kuulokenurkka | over-ear |

Never edited by hand: a change is a new fetch at a named commit, and make-eq-fixtures.py run again.
