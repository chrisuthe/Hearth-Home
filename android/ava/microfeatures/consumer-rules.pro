# The native frontend builds ProcessOutput through JNI GetMethodID("<init>",
# "([FI)V"), which R8 cannot see, so it would strip the constructor.
-keep class com.example.microfeatures.ProcessOutput {
    <init>(float[], int);
}
