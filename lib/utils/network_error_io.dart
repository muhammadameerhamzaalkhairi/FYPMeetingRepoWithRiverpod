import 'dart:io';

bool isNetworkError(Object error) =>
    error is SocketException || error is HttpException || error is TlsException;
