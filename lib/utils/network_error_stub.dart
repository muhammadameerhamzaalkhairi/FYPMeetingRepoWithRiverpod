// Browser HTTP clients surface ClientException, which is also checked by the
// shared mapper. Keep dart:io out of web builds.
bool isNetworkError(Object error) => false;
