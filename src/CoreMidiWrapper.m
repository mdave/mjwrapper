/*
 * CoreMIDIWrapper.m
 *
 * This Objective-C file provides a simple wrapper around Apple's CoreMIDI
 * library, bridging it to the various Java classes using the JNI. The file is
 * split into several different sections. Firstly, it defines two Objective-C
 * classes:
 *
 * - MIDIListener: Given the unique ID of a MIDI output port and a Java
 *   callback object (which is of class CoreMidiTransmitter), this is designed
 *   to create a virtual socket which listens to the output of the MIDI
 *   device. It then calls the appropriate function inside CoreMidiTransmitter
 *   to transmit the data to the Java application.
 *
 * - MIDISender: Does pretty much the same as above, but accepts data from a
 *   CoreMidiReceiver and sends to a MIDI IN port.
 *
 * These Objective-C classes are then used in several native JNI functions
 * inside the various classes defined in this directory. When it's all put
 * together, Mac OS X MIDI devices should be accessible to Java applications.
 *
 * DISCLAIMER: I am not a Java programmer, and this is the very first time
 * using CoreMIDI or any other MIDI framework for that matter. I have made
 * many assumptions along the way which may invalidate this library
 * completely. If you have suggestions, or better, fixes and improvements,
 * then please e-mail me!
 *
 * Copyright (C) 2009 David Moxey (dave@xyloid.org)
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 * 
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc., 51
 * Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

// Import Cocoa and CoreMIDI headers.
#import <Foundation/Foundation.h>
#import <CoreMIDI/MIDIServices.h>

// Java native function declarations automatically generated using javah.
#include "CoreMidiWrapper.h"
#include "CoreMidiDevice.h"
#include "CoreMidiTransmitter.h"
#include "CoreMidiReceiver.h"

// Pointer to the current JavaVM instance. Used to find current JNIEnv from
// different threads.
JavaVM *jvm;

static void MIDIReadHandler(const MIDIPacketList *pkts, void *readRef, void *srcRef);

// --------------------------------------------------------------------
// MIDIListener class: simple subclass of NSObject which is designed to store
// resources associated with the listening virtual socket, and deal with data
// sent back to it through the MIDIReadHandler callback function (defined
// below).
// --------------------------------------------------------------------
@interface MIDIListener : NSObject {
  SInt32          uniqueID;   // Unique ID of the MIDI OUT port of the device.
  MIDIClientRef   midiClient;
  MIDIPortRef     inputPort;
  MIDIEndpointRef source;
  jmethodID       jCbFunc;    // Global reference to the appropriate callback function.
  jobject         jCbObj;     // Callback object.
}
- (id)   initWithUniqueID:(SInt32)ID jCallback:(jobject)cb;
- (void) handleData:(NSData *)pkts;
- (void) dealloc;
@end 

@implementation MIDIListener

- (id) initWithUniqueID:(SInt32)ID jCallback:(jobject)cb{
  //  JNF_COCOA_ENTER();

  OSStatus       status;
  MIDIObjectType objType;
  JNIEnv        *env;
  jclass         cls;
  
  if (self = [super init]) {
    // Assign local variables. Hopefully cb is a global reference or
    // we're a bit screwed.
    uniqueID = ID;
    jCbObj   = cb;
    
    // Grab a fresh copy of the JNIEnv just to be on the safe side since we're
    // probably being called from another thread. Then establish a global
    // reference to the callback function inside jCbObj.
    (*jvm)->AttachCurrentThread(jvm, (void **)&env, NULL);
    
    cls     = (*env)->GetObjectClass(env, jCbObj);
    jCbFunc = (*env)->GetMethodID(env, cls, "receivedData", "([B)V");
    
    // Given the unique ID, we now grab the source endpoint.
    MIDIObjectFindByUniqueID(uniqueID, &source, &objType);
    
    // Shouldn't happen! We should always be passed a source, not say a device
    // or any other MIDI object.
    if (objType != kMIDIObjectType_Source)
      return nil;
    
    // Now hook up the input port to the endpoint source. After this is done,
    // we should start to receive data. TODO: this really needs to be error
    // checked.
    MIDIClientCreate(CFSTR("CoreMidiListener"), NULL, NULL, &midiClient);
    MIDIInputPortCreate(midiClient, CFSTR("CoreMidiListenerInput"), MIDIReadHandler, self, &inputPort);
    MIDIPortConnectSource(inputPort, source, NULL);    
  }
  
  return self;
}

/*
 * Handle incoming data. This function will be called by the MIDIReadHandler
 * function below.
 */
- (void) handleData:(NSData *)pkts {
  JNIEnv           *env;
  int               i;
  MIDIPacketList   *packets = (MIDIPacketList *)[pkts bytes];
  const MIDIPacket *packet;
  jbyteArray        bytes;
  
  // Grab ourselves a pointer to the current thread environment, and
  // synchronise across threads through the monitors.
  (*jvm)->AttachCurrentThread(jvm, (void **)&env, NULL);
  (*env)->MonitorEnter(env, jCbObj);
  
  // Process the packets we've received.
  packet = &packets->packet[0];

  for (i = 0; i < packets->numPackets; i++) {
    // Construct Java-equivalent bytes array.
    bytes  = (*env)->NewByteArray(env, packet->length);
    (*env)->SetByteArrayRegion(env, bytes, 0, packet->length, (jbyte *)packet->data);

    // Call our Java function and pass it data.
    (*env)->CallVoidMethod(env, jCbObj, jCbFunc, bytes);

    // Free up memory and move onto the next packet.
    (*env)->DeleteLocalRef(env, bytes);
    packet = MIDIPacketNext(packet);
  }
  
  (*env)->MonitorExit(env, jCbObj);
}

/*
 * Free up the resources we created earlier.
 */
- (void) dealloc {
  JNIEnv *env;
  
  // Release our global reference to the callback function.
  (*jvm)->AttachCurrentThread(jvm, (void **)&env, NULL);
  (*env)->DeleteGlobalRef(env, jCbObj);
  
  // Do things in reverse: disconnect from source, dispose of the virtual port
  // and then the client.
  MIDIPortDisconnectSource(inputPort, source);
  MIDIPortDispose(inputPort);
  MIDIClientDispose(midiClient);
  
  [super dealloc];
}
@end

// --------------------------------------------------------------------
// Helper functions for classes and other functions.
// --------------------------------------------------------------------

// This function was submitted by Douglas Casey Tucker and apparently derived
// largely from PortMidi.
CFStringRef EndpointName(MIDIEndpointRef endpoint, bool isExternal)
{
  CFMutableStringRef result = CFStringCreateMutable( NULL, 0 );
  CFStringRef        str;
  
  // Begin with the endpoint's name.
  str = NULL;
  MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &str);
  if (str != NULL) {
    CFStringAppend(result, str);
    CFRelease(str);
  }
  
  MIDIEntityRef entity = NULL;
  MIDIEndpointGetEntity(endpoint, &entity);
  if (entity == NULL)
    // probably virtual
    return result;
  
  if (CFStringGetLength(result) == 0) {
    // endpoint name has zero length -- try the entity
    str = NULL;
    MIDIObjectGetStringProperty(entity, kMIDIPropertyName, &str);
    if (str != NULL) {
      CFStringAppend(result, str);
      CFRelease(str);
    }
  }
  
  // now consider the device's name
  MIDIDeviceRef device = NULL;
  MIDIEntityGetDevice(entity, &device);
  if (device == NULL)
    return result;

  str = NULL;
  MIDIObjectGetStringProperty(device, kMIDIPropertyName, &str);
  if (CFStringGetLength(result) == 0) {
    CFRelease(result);
    return str;
  }
  if (str != NULL) {
    // if an external device has only one entity, throw away
    // the endpoint name and just use the device name
    if (isExternal && MIDIDeviceGetNumberOfEntities(device) < 2) {
      CFRelease(result);
      return str;
    } else {
      if (CFStringGetLength(str) == 0) {
        CFRelease(str);
        return result;
      }
      // does the entity name already start with the device name?
      // (some drivers do this though they shouldn't)
      // if so, do not prepend
      if (CFStringCompareWithOptions(result, /* endpoint name */
	  str /* device name */,
	  CFRangeMake(0, CFStringGetLength(str)), 0) != kCFCompareEqualTo) {
	// prepend the device name to the entity name
	if (CFStringGetLength(result) > 0 )
	  CFStringInsert(result, 0, CFSTR(" "));
	CFStringInsert(result, 0, str);
      }
      CFRelease(str);
    }
  }
  return result;
}

// This function was submitted by Douglas Casey Tucker and apparently
// derived largely from PortMidi.
static CFStringRef ConnectedEndpointName(MIDIEndpointRef endpoint)
{
  CFMutableStringRef result = CFStringCreateMutable(NULL, 0);
  CFStringRef        str;
  OSStatus           err;
  int                i;

  // Does the endpoint have connections?
  CFDataRef          connections = NULL;
  int                nConnected = 0;
  bool               anyStrings = false;

  err = MIDIObjectGetDataProperty(endpoint, kMIDIPropertyConnectionUniqueID, &connections);

  if (connections != NULL) {
    // It has connections, follow them
    // Concatenate the names of all connected devices
    nConnected = CFDataGetLength( connections ) / sizeof(MIDIUniqueID);
    if ( nConnected ) {
      const SInt32 *pid = (const SInt32 *)(CFDataGetBytePtr(connections));
      for ( i=0; i<nConnected; ++i, ++pid ) {
        MIDIUniqueID id = EndianS32_BtoN( *pid );
        MIDIObjectRef connObject;
        MIDIObjectType connObjectType;
        err = MIDIObjectFindByUniqueID( id, &connObject, &connObjectType );
        if ( err == noErr ) {
          if ( connObjectType == kMIDIObjectType_ExternalSource  ||
              connObjectType == kMIDIObjectType_ExternalDestination ) {
            // Connected to an external device's endpoint (10.3 and later).
            str = EndpointName( (MIDIEndpointRef)(connObject), true );
          } else {
            // Connected to an external device (10.2) (or something else, catch-
            str = NULL;
            MIDIObjectGetStringProperty( connObject, kMIDIPropertyName, &str );
          }
          if ( str != NULL ) {
            if ( anyStrings )
              CFStringAppend( result, CFSTR(", ") );
            else anyStrings = true;
            CFStringAppend( result, str );
            CFRelease( str );
          }
        }
      }
    }
    CFRelease( connections );
  }
  if ( anyStrings )
    return result;

  // Here, either the endpoint had no connections, or we failed to obtain names 
  return EndpointName( endpoint, false );
}

/*
 * Function called when library is first loaded. Store pointer to jvm
 * instance.
 */
jint JNI_OnLoad(JavaVM *vm, void *reserved) {
  jvm = vm;
  return JNI_VERSION_1_2;
}

/*
 * Handler function necessary to interface MIDIListener with the pure-C
 * CoreMIDI API. Designed to be reasonably fast - probably it's possible to do
 * it more efficiently.
 */
void MIDIReadHandler(const MIDIPacketList *pkts, void *readRef, void *srcRef) {
  NSAutoreleasePool *pool     = [[NSAutoreleasePool alloc] init];
  MIDIListener      *listener = (MIDIListener *)readRef;
  NSData            *data;
  int                i, size, pktsize = 0;
  const MIDIPacket  *packet;
  
  size   = sizeof(UInt32);
  packet = &pkts->packet[0];
  
  for (i = 0; i < pkts->numPackets; i++) {
    size    += offsetof(MIDIPacket, data) + packet->length;
    pktsize += packet->length;
    packet   = MIDIPacketNext(packet);
  }

  data = [NSData dataWithBytes:pkts length:size];

  [listener performSelectorOnMainThread:@selector(handleData:) withObject:data waitUntilDone:NO];
  [pool release];
}

/*
 * Takes an input NSString and current JNIEnv and returns a JString. The
 * reference is NOT global.
 */
jstring nss2js(NSString *input, JNIEnv *env) {
  jsize   buflength = [input length];
  unichar buffer[buflength];

  [input getCharacters:buffer];
  return (*env)->NewString(env, (jchar *)buffer, buflength);
}

// --------------------------------------------------------------------
// NATIVE FUNCTION IMPLEMENTATIONS
// --------------------------------------------------------------------

/*
 * Wrapper to obtain all active MIDI devices. We then call the appropriate
 * Java function to populate device info (i.e. transmitters, receivers, etc).
 */
JNIEXPORT void JNICALL Java_CoreMidiWrapper_initMIDIDevices(JNIEnv *env, jobject obj) {
  jclass          cls = (*env)->GetObjectClass(env, obj);
  jmethodID       mid = (*env)->GetMethodID(env, cls, "addMIDIDevice", "(I)V");
  int             i, numSources, numDestinations;
  MIDIEndpointRef portRef;
  SInt32          uniqueID;
  
  numSources      = MIDIGetNumberOfSources();
  numDestinations = MIDIGetNumberOfDestinations();
  
  // Cycle through all available sources and destinations. Create a new MIDI
  // device for each source and destination.
  for (i = 0; i < numSources; i++) {
    portRef  = MIDIGetSource(i);
    MIDIObjectGetIntegerProperty(portRef, kMIDIPropertyUniqueID, &uniqueID);
    (*env)->CallVoidMethod(env, obj, mid, (jint)uniqueID);
  }

  for (i = 0; i < numDestinations; i++) {
    portRef  = MIDIGetDestination(i);
    MIDIObjectGetIntegerProperty(portRef, kMIDIPropertyUniqueID, &uniqueID);
    (*env)->CallVoidMethod(env, obj, mid, (jint)uniqueID);
  }
}

/*
 * Main function to populate the device info.
 */
JNIEXPORT void JNICALL Java_CoreMidiDevice_populateDeviceInfo(JNIEnv *env, jobject obj) {
  jfieldID        jfName, jfModel, jfMfct, jfuniqueID;
  jclass          cls = (*env)->GetObjectClass(env, obj);
  jint            uniqueID;
  jstring         jstr;
  MIDIObjectType  objType;
  MIDIEndpointRef portRef;
  NSDictionary   *portProps;
  NSString       *pName, *pModel, *pMfct;
  int             i;
  jmethodID       msetSource;
  jmethodID       msetDestination;
  
  jfuniqueID      = (*env)->GetFieldID (env, cls, "uniqueID", "I");
  jfName          = (*env)->GetFieldID (env, cls, "name",     "Ljava/lang/String;");
  jfModel         = (*env)->GetFieldID (env, cls, "model",    "Ljava/lang/String;");
  jfMfct          = (*env)->GetFieldID (env, cls, "mfct",     "Ljava/lang/String;");
  msetSource      = (*env)->GetMethodID(env, cls, "setSource",      "(I)V");
  msetDestination = (*env)->GetMethodID(env, cls, "setDestination", "(I)V");

  // Grab unique ID from Java object.
  uniqueID   = (*env)->GetIntField(env, obj, jfuniqueID);
  MIDIObjectFindByUniqueID(uniqueID, &portRef, &objType);
  
  // TODO: do something useful here.
  if (objType != kMIDIObjectType_Source && objType != kMIDIObjectType_Destination)
    return;
  
  // Get MIDI object properties.
  //MIDIObjectGetProperties(portRef, (CFPropertyListRef *)&portProps, YES);
  
  pName = (NSString *)ConnectedEndpointName(portRef);
  (*env)->SetObjectField(env, obj, jfName,  nss2js(pName,  env));
  
  /*
  pName  = [midiDeviceProps objectForKey:(NSString *)kMIDIPropertyName];
  pModel = [midiDeviceProps objectForKey:(NSString *)kMIDIPropertyModel];
  pMfct  = [midiDeviceProps objectForKey:(NSString *)kMIDIPropertyManufacturer];

  (*env)->SetObjectField(env, obj, jfName,  nss2js(pName,  env));
  (*env)->SetObjectField(env, obj, jfModel, nss2js(pModel, env));
  (*env)->SetObjectField(env, obj, jfMfct,  nss2js(pMfct,  env));
  */
  
  if (objType == kMIDIObjectType_Source)
    (*env)->CallVoidMethod(env, obj, msetSource,      (jint)uniqueID);
  else
    (*env)->CallVoidMethod(env, obj, msetDestination, (jint)uniqueID);
}

/*
 * Create a MIDIListener on this source which will continue until the close()
 * function is called.
 */
JNIEXPORT void JNICALL Java_CoreMidiTransmitter_startListener(JNIEnv *env, jobject obj) {
  jfieldID      jfuniqueID, jftransPtr;
  jclass        cls = (*env)->GetObjectClass(env, obj);
  jint          uniqueID;
  jlong         transPtr;
  jobject       globalRef;
  MIDIListener *listener;

  // Grab source unique ID.
  jfuniqueID = (*env)->GetFieldID  (env, cls, "uniqueID", "I");
  jftransPtr = (*env)->GetFieldID  (env, cls, "transPtr", "J");
  uniqueID   = (*env)->GetIntField (env, obj, jfuniqueID);
  transPtr   = (*env)->GetLongField(env, obj, jftransPtr);
  
  // Create global reference to Java callback object in order to avoid our
  // local reference suddenly disappearing at some point.
  globalRef = (*env)->NewGlobalRef(env, obj);
  
  if (transPtr != 0) {
    listener = (MIDIListener *)transPtr;
    [listener dealloc];
  }
  
  // Create MIDI listener.
  listener = [[MIDIListener alloc] initWithUniqueID:(SInt32)uniqueID jCallback:globalRef];

  (*env)->SetLongField(env, obj, jftransPtr, (jlong)listener);
}

JNIEXPORT void JNICALL Java_CoreMidiTransmitter_stopListener(JNIEnv *env, jobject obj) {
  jfieldID      jftransPtr;
  jclass        cls = (*env)->GetObjectClass(env, obj);
  jlong         transPtr;
  MIDIListener  *listener;
  
  jftransPtr = (*env)->GetFieldID  (env, cls, "transPtr", "J");
  transPtr   = (*env)->GetLongField(env, obj, jftransPtr);

  if (transPtr == 0)
    return;

  listener = (MIDIListener *)transPtr;
  [listener dealloc];

  (*env)->SetLongField(env, obj, jftransPtr, (jlong)0);
}

// --------------------------------------------------------------------
// MIDISender class: designed to do nothing but be a wrapper around a
// virtual MIDI output port. Typically we store a reference to this
// guy in the Java class.
// --------------------------------------------------------------------
@interface MIDISender : NSObject {
  SInt32 uniqueID;
  MIDIEndpointRef destPort;
  MIDIPortRef outputPort;
  MIDIClientRef midiClient;
}
- (id)initWithUniqueID:(SInt32)uniqueID;
- (void)dealloc;
- (void)sendMessage:(NSData *)message;
@end

@implementation MIDISender
/*
 * Simple constructor. First find the right destination port (i.e. the
 * device's MIDI IN port. Then, for regular MIDI messages, we create a virtual
 * port through which they will be sent. Note Sysex messages don't need this.
 */
- (id)initWithUniqueID:(SInt32)ID {
  if (self = [super init]) {
    MIDIObjectType objType;
    
    // TODO: error checking.
    uniqueID = ID;
    MIDIObjectFindByUniqueID(uniqueID, &destPort, &objType);
    MIDIClientCreate(CFSTR("CoreMidiOutput"), NULL, NULL, &midiClient);
    MIDIOutputPortCreate(midiClient, CFSTR("CoreMidiOutputPort"), &outputPort);
  }
  return self;
}

/*
 * Clean up after ourselves.
 */
- (void)dealloc {
  MIDIPortDispose  (outputPort);
  MIDIClientDispose(midiClient);
  [super dealloc];
}

/*
 * Routine to send messages to our recipient. As input we have an NSData
 * object which contains the data to send. Assume that timestamp = 0;
 * i.e. send to device immediately. Also assume that all sysex messages are >
 * 3 bytes long (a reasonable assumption!).
 */
- (void)sendMessage:(NSData *)data {
  MIDIPacketList  packetList;
  MIDIPacket     *firstPacket;
  int             length = [data length];
  
  // Set up initial packet information. Guaranteed a single packet at
  // a time.
  packetList.numPackets  = 1; 
  firstPacket            = &packetList.packet[0];
  firstPacket->timeStamp = 0;
  firstPacket->length    = length;
  
  if (length > 3) {
    // Now have to split into two cases; sysex or not sysex. Right now we take
    // the not-too-stupid-but-possibly-incorrect assumption that if the length
    // > 3 then this is a sysex message. Otherwise we just regard it as a
    // standard MIDI message;
    MIDISysexSendRequest *req;
    Byte                 *msg;
    
    // TODO: This memory is not freed after use! Probably need to write a
    // small class to encompass each MIDISysexSendRequest.
    msg = malloc(length);
    req = malloc(sizeof(MIDISysexSendRequest));
    
    // Copy sysex message into buffer.
    memcpy(msg, [data bytes], length);
    
    req->destination      = destPort;
    req->data             = (const Byte *)msg;
    req->bytesToSend      = length;
    req->complete         = false;
    req->completionProc   = NULL;
    req->completionRefCon = NULL; // TODO: use this callback to free memory!
     
    // MIDISendSysex is special, sends data asynchronously.
    MIDISendSysex(req);
  } else {
    // If we have a regular message then copy the data over from NSData object
    // and send synchronously using MIDISend.
    memcpy(firstPacket->data, [data bytes], length);
    MIDISend(outputPort, destPort, &packetList);
  }
  
  [data release];
}
@end

/*
 * Create a virtual output port using the MIDISender class which will be
 * responsible for caching the ports and resources associated with sending
 * messages to this device.
 */
JNIEXPORT void JNICALL Java_CoreMidiReceiver_createOutputPort(JNIEnv *env, jobject obj) {
  jfieldID    jfuniqueID, jfsenderPtr;
  jclass      cls = (*env)->GetObjectClass(env, obj);
  jint        uniqueID;
  jlong       senderPtr;
  MIDISender *sender;

  // Grab the unique ID of the MIDI IN port, stored inside the calling Java
  // object.
  jfuniqueID  = (*env)->GetFieldID  (env, cls, "uniqueID",  "I");
  jfsenderPtr = (*env)->GetFieldID  (env, cls, "senderPtr", "J");
  uniqueID    = (*env)->GetIntField (env, obj, jfuniqueID);
  senderPtr   = (*env)->GetLongField(env, obj, jfsenderPtr);
  
  if (senderPtr != 0) {
    sender    = (MIDISender *)senderPtr;
    [sender dealloc];
  }
  
  // Create MIDI sender object - we don't want to create a new port every time
  // to send a single message.
  sender = [[MIDISender alloc] initWithUniqueID:uniqueID];
  
  // Store pointer to sender object inside Java object.
  (*env)->SetLongField(env, obj, jfsenderPtr, (jlong)sender);
}

JNIEXPORT void JNICALL Java_CoreMidiReceiver_closeOutputPort(JNIEnv *env, jobject obj) {
  jfieldID    jfsenderPtr;
  jclass      cls = (*env)->GetObjectClass(env, obj);
  jlong       senderPtr;
  MIDISender *sender;

  // Grab the unique ID of the MIDI IN port, stored inside the calling Java
  // object.
  jfsenderPtr = (*env)->GetFieldID  (env, cls, "senderPtr", "J");
  senderPtr   = (*env)->GetLongField(env, obj, jfsenderPtr);

  if (senderPtr == 0)
    return;
  
  sender = (MIDISender *)senderPtr;
  [sender dealloc];
  
  // Store pointer to sender object inside Java object.
  (*env)->SetLongField(env, obj, jfsenderPtr, (jlong)0);
}

/*
 * Send a MIDI message using the appropriate MIDISender object.
 */
JNIEXPORT void JNICALL Java_CoreMidiReceiver_sendMessage(JNIEnv *env, jobject obj, jbyteArray message, jlong timestamp) {
  jfieldID    jfsenderPtr;
  jlong       senderPtr;
  jbyte      *buf;
  jclass      cls = (*env)->GetObjectClass(env, obj);
  int         arrayLength = (*env)->GetArrayLength(env, message);;
  MIDISender *sender;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  buf         = malloc(arrayLength);
  (*env)->GetByteArrayRegion(env, message, 0, arrayLength, buf);
  
  // Query Java object for the pointer to the right MIDISender object, then
  // package up our data and send the message.
  jfsenderPtr = (*env)->GetFieldID(env, cls, "senderPtr", "J");
  senderPtr   = (*env)->GetLongField(env, obj, jfsenderPtr);
  sender      = (MIDISender *)senderPtr;
  
  [sender sendMessage:[[NSData dataWithBytesNoCopy:buf length:arrayLength] retain]];
  [pool release];
}
