/*
 * CoreMidiReceiver.java: simple receiver object; transmits data to another
 * CoreMIDI device on the system.
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
 * CoreMidiReceiver sends MIDI messages received from a Transmitter to some
 * MIDI IN port of a CoreMIDI device. It does this via use of a native
 * MIDISender object (see CoreMidiWrapper.m).
 */
public class CoreMidiReceiver implements Receiver {
    private int  uniqueID;
    private long senderPtr;
    private CoreMidiDevice parentDevice;
    
    /**
     * Class constructor.
     */
    public CoreMidiReceiver(CoreMidiDevice _parentDevice, int _uniqueID) {
	uniqueID     = _uniqueID;
	senderPtr    = 0L;
	parentDevice = _parentDevice;
    }

    /**
     * Set up the MIDISender object.
     */
    public native void createOutputPort();

    /**
     * Close the MIDISender object and free memory.
     */
    public native void closeOutputPort();

    /**
     * This function is called by the send() function. It sends the message
     * with timestamp to the appropriate MIDI IN port defined by uniqueID.
     */
    private synchronized native void sendMessage(byte[] message, long timestamp);
    
    /**
     * Close this receiver: clean up the MIDISender if it's open and inform
     * parentDevice that we've closed.
     */
    public void close() {
	if (senderPtr != 0L) {
	    closeOutputPort();
	    parentDevice.setOpenFlag(false);
	}
    }

    /**
     * Very simple wrapper function which calls the native sendMessage
     * function with the contents of message.
     */
    public synchronized void send(MidiMessage message, long timestamp) {
	try {
	    byte[] data = message.getMessage();
	    this.sendMessage(data, 0);
	} catch (Exception e) {
	    // TODO: do something useful here.
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
}