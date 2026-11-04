# HRTF credits

The head-related transfer functions of the spatial audio (docs/features.md #21) are measurements of the SADIE II
database, University of York, under the Apache License 2.0 (`LICENSE-Apache-2.0.txt` in this folder). They were
downloaded from https://www.york.ac.uk/sadie-project/database.html (48 kHz, 256-tap SOFA files), read 2026-11-03.

Please cite the database when you use it: C. Armstrong, L. Thresh, D. Murphy and G. Kearney, "A Perceptual
Evaluation of Individual and Non-Individual HRTFs: A Case Study of the SADIE II Database", Applied Sciences 8(11),
2029 (2018), doi:10.3390/app8112029.

Changes made (the Apache License's section 4): each set was converted by `app/tools/hrtf_pack.gd` with the engine's
BinauralRenderer: equalised to the diffuse field, the interaural delay taken out of each response, cut to 128 taps,
interpolated onto a grid of 48 azimuths (7.5 degrees apart) by 14 elevations (-40 to 90 degrees, 10 apart), made
minimum-phase, smoothed across azimuth (log magnitudes, weights -1, 4, 10, 4, -1 over 16), the measured delays
replaced by a spherical head's fitted to them, and stored as 16-bit samples with the delays beside them (`.fhrtf`,
version 3). On loading, the engine fills in the azimuths between (1.875 degrees apart).

| File | SADIE II subject | What |
|---|---|---|
| `sadie2_d1.fhrtf` | D1 | a dummy head, shown as "Dummy head A" (the default); the database names it Neumann KU100 |
| `sadie2_d2.fhrtf` | D2 | a dummy head, shown as "Dummy head B"; the database names it GRAS KEMAR 45BC |
| `sadie2_h3.fhrtf` | H3 | a listener |
| `sadie2_h4.fhrtf` | H4 | a listener |
| `sadie2_h5.fhrtf` | H5 | a listener |
| `sadie2_h6.fhrtf` | H6 | a listener |

Sets the app fetches only when asked (each with its licence shown first; not part of this repository): the MIT
dummy head (free to use, cite Gardner and Martin), HUTUBS listener 1 (CC BY 4.0), ARI listener NH2 (CC BY-SA 4.0) and CIPIC
subject 003 (the database's own terms). They come from the SOFA collection at https://sofacoustics.org/data/database/
and are converted on the device.
