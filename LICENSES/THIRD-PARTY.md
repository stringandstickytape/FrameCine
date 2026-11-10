# Keyboard word list

`app/keyboard/words.tsv.gz` is a modified selection from SCOWL 2020.12.07, by Kevin Atkinson, with US
spellings and popularity classes from levels 10–50. Only lowercase ASCII words are included. These classes are
frequency priors, not measured counts. The shipped selection contains 60,000 words, compressed with a fixed
gzip timestamp. The source selection is independent of local files or privacy filters.

Source: <https://wordlist.aspell.net/>; the exact source archive, checksum and reproducible selection are in
`tools/build_keyboard_words.py`. Run `python3 tools/build_keyboard_words.py`, or pass `--archive` with the pinned
tarball for an offline rebuild. The applicable permissive notices and public-domain credits are retained in
`keyboard-words.txt`. Redistribution and commercial use are allowed without a fee or share-alike terms.

The existing package's other notices are assembled by `tools/package.sh`.
