# Bundled typefaces

The files are unmodified upstream binary font distributions. Each project's
complete SIL Open Font License 1.1 and its copyright and reserved-name notices
are supplied beside this document. No runtime network fetch is required.

| Family | Version in font | Weights | Upstream source | License |
| --- | --- | --- | --- | --- |
| Hahmlet | 1.002 | Regular, Medium, SemiBold, Bold | [hyper-type/hahmlet](https://github.com/hyper-type/hahmlet/tree/f9c5dac25d88015e9f0953253cec1a71854b7d24/fonts/otf) | [Hahmlet-OFL.txt](Hahmlet-OFL.txt) |
| Pretendard | 1.309 | Regular, Medium, SemiBold | [orioncactus/pretendard](https://github.com/orioncactus/pretendard/tree/7aeb0698819be2b4097dae8ec8fe6a795e5cf3ae/packages/pretendard/dist/public/static) | [Pretendard-OFL.txt](Pretendard-OFL.txt) |
| GFS Didot | 1.0 | Regular | [Google Fonts distribution](https://github.com/google/fonts/tree/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl/gfsdidot) | [GFSDidot-OFL.txt](GFSDidot-OFL.txt) |

Original font metadata credits Hahmlet Project Authors; Kil Hyung-jin and the
upstream Source, Inter and M+ projects for Pretendard; and Takis Katsoulidis,
George D. Matthiopoulos and the Greek Font Society for GFS Didot. The
associated license texts preserve their fuller notices.

Hahmlet supplies 2,788 precomposed Hangul syllables and no Greek. Pretendard
supplies all 11,172 precomposed Hangul syllables and the required polytonic
Greek characters. GFS Didot supplies the required polytonic Greek but no
Hangul. Typography resources should explicitly use the bundled Pretendard
font as a fallback where appropriate; do not rely on operating-system fonts.
No generated subset is used, so arbitrary supported runtime strings remain
available.
