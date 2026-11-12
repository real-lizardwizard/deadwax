// SQLite for DeadwaxCore's download store (notes/ios-specs/phase2-downloads.md 8.2): Apple's SDKs carry it, and
// Linux gets it from libsqlite3-dev - so the schema, its migrations and every query are tested on Linux too.
#include <sqlite3.h>
