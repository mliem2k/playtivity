# Keep stack traces readable in bug reports.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# OkHttp 5 and Compose ship their own consumer rules; this app adds none beyond the manifest components,
# which R8 keeps automatically.
