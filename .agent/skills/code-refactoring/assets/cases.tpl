# Cases for behavior-snapshot. One case per line: NAME<TAB>COMMAND LINE. Lines starting with # are ignored.
# Cover each public command, wrapper, and function: normal use, no arguments, invalid input, --help.
# Cases are deterministic: no dates, process ids, random values, or network.
# The sandbox sets HOME, PREFIX, and TMPDIR to temporary directories; stub commands a case calls with --stub.
no-args	my_command
help	my_command --help
bad-option	my_command --bad-option
wrapper-version	my_wrapper --version
