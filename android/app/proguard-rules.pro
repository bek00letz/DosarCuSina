# What the release build's shrinking must keep, beyond the rules each library ships with its own
# (Room keeps the database it generates, kotlinx.serialization and coroutines theirs).

# The persistence log names a failure by the kind of error, its class's name (PersistenceLog.kindOf),
# never its message: those names must stay readable in a release build.
-keepnames class * extends java.lang.Throwable

# The catalogs, the words and the travel rules are read from the modules' resources by their full
# path (/com/ar/dosarcusina/...), which shrinking leaves as they are; nothing here depends on a class
# keeping its name or package.
