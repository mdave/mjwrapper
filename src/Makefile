CC=cc
LD=cc
LDFLAGS=-dynamiclib -framework JavaVM -framework CoreMIDI -framework Foundation -arch x86_64 -arch ppc
CFLAGS=-c -I/System/Library/Frameworks/JavaVM.framework/Headers -arch x86_64 -arch ppc
JHEADS=CoreMidiWrapper.h CoreMidiDevice.h CoreMidiTransmitter.h CoreMidiReceiver.h

all: mjwrapper.jar
	cp mjwrapper.jar libmjwrapper.jnilib ../lib

clean:
	rm -f mjwrapper.jar libmjwrapper.jnilib *.class CoreMidiWrapper.o *.h

install: all
	cp ../lib/mjwrapper.jar ../lib/libmjwrapper.jnilib /Library/Java/Extensions

mjwrapper.jar: libmjwrapper.jnilib CoreMidiWrapper.class
	jar cvf0 mjwrapper.jar *.class META-INF

libmjwrapper.jnilib: ${JHEADS} CoreMidiWrapper.o
	cc CoreMidiWrapper.o -o libmjwrapper.jnilib ${LDFLAGS}

CoreMidiWrapper.o: CoreMidiWrapper.m
	cc ${CFLAGS} CoreMidiWrapper.m -o CoreMidiWrapper.o

CoreMidiWrapper.h: CoreMidiWrapper.class
	javah -jni CoreMidiWrapper

CoreMidiDevice.h: CoreMidiWrapper.class
	javah -jni CoreMidiDevice

CoreMidiTransmitter.h: CoreMidiWrapper.class
	javah -jni CoreMidiTransmitter

CoreMidiReceiver.h: CoreMidiWrapper.class
	javah -jni CoreMidiReceiver

CoreMidiWrapper.class: CoreMidiWrapper.java CoreMidiDevice.java CoreMidiTransmitter.java CoreMidiReceiver.java
	javac CoreMidiWrapper.java
