#ifndef BJC85_RECOVERY_H
#define BJC85_RECOVERY_H
#include <stdbool.h>
#include <stddef.h>
/* Shared by every native client, independent of a checkout or bundle location.
 * Call begin/finish only while holding the common USB lease. Unknown = blocked. */
bool bjc_recovery_path(char *path, size_t capacity);
bool bjc_recovery_required(void);
bool bjc_recovery_begin(const char *operation);
bool bjc_recovery_finish_safe(void);
#endif
