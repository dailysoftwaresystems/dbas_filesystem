#ifndef FLUTTER_PLUGIN_DBAS_FILESYSTEM_PLUGIN_H_
#define FLUTTER_PLUGIN_DBAS_FILESYSTEM_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _DbasFilesystemPlugin DbasFilesystemPlugin;
typedef struct {
  GObjectClass parent_class;
} DbasFilesystemPluginClass;

FLUTTER_PLUGIN_EXPORT GType dbas_filesystem_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void dbas_filesystem_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_DBAS_FILESYSTEM_PLUGIN_H_
