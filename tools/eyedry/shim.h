/* Replacement for gets(), which was removed from C11 and current glibc. Same behaviour: reads a line from stdin
   and strips the newline. Included before eyedry.c with gcc -include. */
#include <ctype.h>
#include <string.h>
#include <stdio.h>
static char *gets_shim(char *s)
{
    if (!fgets(s, 4000, stdin))
        return NULL;
    size_t n = strlen(s);
    if (n && s[n - 1] == '\n')
        s[n - 1] = 0;
    return s;
}
#define gets(s) gets_shim(s)
