These are examples of how the script behave. Here is how the *_examples.txt files works:

`!#` is a comment. If a line only has such a comment, the whole line is removed.
Otherwise, the `!# ` and everything after is removed.

The examples are in 4 steps:
1) input haml
2) extracted ruby
3) the corrected ruby
4) the corrected haml
Each steps is delimited by a line with ---

Examples start with a !!! followed by the name

If an example's steps contains the ^ character, it will be executed twice:
* once with the ^ replaced by -, the ^^ removed and the %% are removed
* once with the ^ replaced by =, the ^^ replaces by the special prefix
  used by haml-lint in the ruby code to handle = scripts,
  and the %% replaced by as many spaces as takes (to indent multi-line scripts)
This way, the same examples can be reused for silent and non-silent scripts.

The files are passed through erb for cases where that is useful.
