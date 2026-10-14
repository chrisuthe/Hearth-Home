# protobuf-lite finds each message's fields by name through reflection
# (MessageSchema), which R8 cannot see, so it would strip or rename them.
-keepclassmembers class com.example.esphomeproto.** extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
