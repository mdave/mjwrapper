/*
 * CoreMidiTransmitter.java: transmitter class - listens for input from a MIDI
 * device, and forwards this on to some Receiver class.
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

import javax.sound.midi.*;
import java.util.*;

/**
 * A listener class which relays MIDI messages from the MIDI OUT port of the
 * device and transmits them to the receiver. The listening is done mostly in
 * the native class, with some reconstruction of the system exclusive messages
 * done in the receviedData() function.
 */
public class CoreMidiTransmitter implements Transmitter {
    private int            uniqueID;     // Unique ID of source port
    private Receiver       receiver;     // Receiver that we want to send
					 // received data to.
    private long           transPtr;     // Pointer to listening object.
    private CoreMidiDevice parentDevice; // Parent MIDI device.
    private boolean        sysexProcess; // True if we are currently in the
					 // middle of processing a sysex
					 // message; false otherwise.
    private byte[]         sysexBuffer;  // Current buffer for sysex messages.
    
    /**
     * Class constructor.
     */
    public CoreMidiTransmitter(CoreMidiDevice _parentDevice, int _uniqueID) {
	uniqueID     = _uniqueID;
	sysexProcess = false;
	transPtr     = 0L;
	parentDevice = _parentDevice;
    }
    
    protected void finalize() throws Throwable {
	super.finalize();
    }
    
    /**
     * Creates a native MIDIListener object (see CoreMidiWrapper.m).
     */
    public native void startListener();

    /**
     * Closes the MIDIListener object (see CoreMidiWrapper.m).
     */
    public native void  stopListener();
    
    /**
     * Called when the MIDIListener object receives data from the MIDI
     * device. This function processes the data and then sends it to the
     * Receiver. In the case of a sysex message, we may need several calls to
     * this function before the message is completed. It's unclear to me
     * whether Java intends for myself or the application developer to handle
     * the case of broken messages, so I have assumed the worst case
     * scenario. mjwrapper will therefore always send <b>complete</b> sysex
     * messages to the receiver.
     */
    public synchronized void receivedData(byte[] midiData) {
	int i;

	// If we don't have a receiver then there's nothing to transmit, so
	// don't bother.
	if (this.receiver == null)
	    return;
	
	// If midiData is empty, then return. This should never happen.
	if (midiData.length == 0)
	    return;
	
	if (midiData[0] == (byte)0xF0 && midiData[midiData.length-1] == (byte)0xF7) {
	    // Check and see if we have a complete sysex message. If we do
	    // then check to see if it's complete. It's not guaranteed that it
	    // is - in fact, 99.99% of the time it seems it isn't - so buffer
	    // existing data until we detect the end of sysex message. Other
	    // messages are only a maximum of three bytes long and are
	    // guaranteed to be intact.
	    SysexMessage msg = new SysexMessage();
	    try {
		msg.setMessage(midiData, midiData.length);
	    } catch (InvalidMidiDataException id) {}
	    receiver.send(msg, -1);
	} else if (this.sysexProcess) {
	    // At this point we're processing an existing sysex message, so
	    // tack new data onto the end of existing data and see if the
	    // message is now complete.
	    int    newLength = sysexBuffer.length + midiData.length;
	    byte[] newBuffer = new byte[newLength];
	    
	    // Copy existing data into new, resized array.
	    System.arraycopy(sysexBuffer, 0, newBuffer, 0,                  sysexBuffer.length);
	    System.arraycopy(midiData,    0, newBuffer, sysexBuffer.length, midiData.length);
	    
	    if (newBuffer[newLength-1] == (byte)0xF7) {
		// At this point message is complete.
		//System.out.println("Complete sysex message: "+getHexString(newBuffer));
		SysexMessage msg = new SysexMessage();
		try {
		    msg.setMessage(newBuffer, newLength);
		} catch (InvalidMidiDataException id) {}

		// Submit message to the receiver.
		sysexProcess = false;
		receiver.send(msg, -1);
	    } else {
		sysexBuffer = newBuffer;
	    }
	} else if (midiData[0] == (byte)0xF0) {
	    // At this point we have the start of a new sysex message, so put
	    // it in a new buffer and copy data over.
	    sysexBuffer  = new byte[midiData.length];
	    sysexProcess = true;
	    System.arraycopy(midiData, 0, sysexBuffer, 0, midiData.length);
	} else {
	    // Otherwise we have something other than a sysex message, so
	    // create a ShortMessage and send to our receiver.
	    ShortMessage msg = new ShortMessage();
	    
	    // Stupid Java stores these things as ints!?? why?!
	    try {
		if (midiData.length == 1)
		    msg.setMessage((int)(midiData[0] & 0xFF));
		else if (midiData.length == 2)
		    msg.setMessage((int)(midiData[0] & 0xFF), (int)(midiData[1] & 0xFF), 0);
		else
		    msg.setMessage((int)(midiData[0] & 0xFF), (int)(midiData[1] & 0xFF), (int)(midiData[2] & 0xFF));
	    } catch (InvalidMidiDataException id) {}

	    // Send our message to the receiver.
	    receiver.send(msg, -1);
	}
    }
    
    /**
     * Helper function for debugging; converts a byte array to
     * string. e.g. [0xff,0x01,0x12] maps to "ff0112".
     */
    private String getHexString(byte[] b) {
	String result = "";
	for (int i = 0; i < b.length; i++) {
	    result += Integer.toString( ( b[i] & 0xff ) + 0x100, 16).substring( 1 );
	}
	return result;
    }

    /**
     * Stop the MIDIListener object if it is currently set up, then inform
     * parentDevice that we've stopped listening (i.e. close the device).
     */
    public void close() {
	if (transPtr != 0L) {
	    stopListener();
	    parentDevice.setOpenFlag(false);
	}
    }
    
    /**
     * Return the current receiver.
     */
    public Receiver getReceiver() {
	return receiver;
    }

    /**
     * Set the receiver object for our MIDI messages.
     */
    public void setReceiver(Receiver _receiver) {
	receiver = _receiver;
    }
}