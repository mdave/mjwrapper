/*
 * CoreMidiWrapper.java: wrapper for a single MIDI transmitter or receiver
 * object.
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

import java.util.*;
import javax.sound.midi.*;

/**
 * CoreMidiDevice is the main wrapper for a CoreMIDI device in OS X. It is
 * designed to wrap either a single MIDI IN port, or a single MIDI OUT
 * port. The reason for this is that there is no way -- as far as I know -- to
 * associate pairs of transmit/receive entities in the CoreMIDI devices
 * themselves. Additionally, this makes the implementation of the Java SPI far
 * easier.
 */
public class CoreMidiDevice implements MidiDevice {
    private MidiDevice.Info   info;               // MidiDevice.Info structure containing device info.
    private int               uniqueID;           // Unique ID of this device.
    private boolean           openFlag = false;   // If the device has one or more open receivers/transmitters this is true.
    
    // Device properties.
    private String            name;
    private String            model;
    private String            mfct;

    // Assoicated transmitter or receiver for this device. Note that the way
    // this is done implies that only one of these will be non-null.
    private CoreMidiTransmitter transmitter;
    private CoreMidiReceiver    receiver;
    
    private long              usStart;
    
    /**
     * Class constructor. Given a unique CoreMIDI ID of either the MIDI IN or
     * OUT port, we call the native populateDeviceInfo() function to set up
     * device information.
     *
     * @param uniqueID The uniqueID of either the MIDI IN or OUT port. 
     */
    public CoreMidiDevice(int _uniqueID) {
	// Initialise the private variables.
	uniqueID      = _uniqueID;
	transmitter   = null;
	receiver      = null;
	usStart       = 0L;
	
	// Call native function which will populate the necessary device
	// info. This function also calls methods in this class to add sources
	// and destinations.
	populateDeviceInfo();
	
	// Create MidiDevice.Info structure.
	info = new Info(name);
    }
    
    /**
     * Given the uniqueID stored as a private variable inside the object, set
     * the device information - name, manufacturer and model if they
     * exist. Also check to see whether the unique ID defines a MIDI IN or
     * MIDI OUT port; if the former then we call setDestination(); the latter
     * we call setSource().
     */
    private native void populateDeviceInfo();

    /**
     * uniqueID defines a MIDI OUT port, so set up a listener on this port.
     *
     * @see CoreMidiTransmitter
     */
    private void setSource(int sourceID) {
	transmitter = new CoreMidiTransmitter(this, sourceID);
    }
    
    /**
     * uniqueID defines a MIDI IN port, so set up a message sender to this
     * port.
     *
     * @see CoreMidiReceiver
     */
    private void setDestination(int destinationID) {
	receiver = new CoreMidiReceiver(this, destinationID);
    }
    
    // ---------------------------------------------------------
    // MidiDevice implementation
    // ---------------------------------------------------------

    /**
     * Get the device information.
     */
    public MidiDevice.Info getDeviceInfo() { 
	return info;
    }
    
    /**
     * Gets maximum number of receivers for this device - 1 if we have a
     * receiver, 0 otherwise.
     */
    public int getMaxReceivers() { 
	if (receiver != null)
	    return 1;
	return 0;
    }
    
    /**
     * Gets maximum number of transmitters for this device - 1 if we have a
     * transmitter, 0 otherwise.
     */
    public int getMaxTransmitters() { 
	if (transmitter != null)
	    return 1;
	return 0;
    }

    /**
     * Gets current position in microseconds since the device was opened.
     */
    public long getMicrosecondPosition() { 
	if (!isOpen()) return 0L;
	return 1000L * System.currentTimeMillis() - usStart;
    }

    /**
     * Return the CoreMidiReceiver device, if it exists. If the receiver is
     * not open, then it opens it (i.e. we start sending to the MIDI IN
     * port). This is the 'implicit' type opening defined in the SPI.
     */
    public Receiver getReceiver() throws MidiUnavailableException { 
	if (receiver == null)
	    throw new MidiUnavailableException("Device has no receivers.");
	if (!openFlag)
	    receiver.createOutputPort();
	return receiver;
    }

    /**
     * Returns the list of all open receivers. In this case however we only
     * have a single receiver at most so construct the list explicitly.
     */
    public List<Receiver> getReceivers() { 
	List<Receiver> tmpList = new ArrayList<Receiver>();

	if (receiver != null && openFlag)
	    tmpList.add(receiver);
	
	return tmpList;
    }
    
    /**
     * Return the CoreMidiTransmitter device, if it exists. If the transmitter
     * is not open, then it opens it (i.e. we start listening to the MIDI OUT
     * port). This is the 'implicit' type opening defined in the SPI.
     */
    public Transmitter getTransmitter() throws MidiUnavailableException { 
	if (transmitter == null)
	    throw new MidiUnavailableException("Device has no transmitters.");
	if (!openFlag)
	    transmitter.startListener();
	return transmitter;
    }
    
    /**
     * Returns the list of all open transmitters. In this case however we only
     * have a single transmitter at most so construct the list explicitly.
     */
    public List<Transmitter> getTransmitters() { 
	List<Transmitter> tmpList = new ArrayList<Transmitter>();
	
	if (transmitter != null && openFlag)
	    tmpList.add(transmitter);
	
	return tmpList;
    }
    
    /**
     * If the device is currently open, then return true. 'open' in this sense
     * means that either the transmitter or receiver object is active.
     */
    public boolean isOpen() { 
	return openFlag;
    }
    
    /**
     * Explicitly open the device for transmission/receiving. Basically we
     * instruct either the transmitter or receiver to start listening or
     * receiving.
     */
    public void open() { 
	int i;

	if (openFlag)
	    return;
	if (receiver != null)
	    receiver.createOutputPort();
	if (transmitter != null)
	    transmitter.startListener();
	
	setOpenFlag(true);
    }
    
    /**
     * Explicitly close the device and close down the receiver/transmitter.
     */
    public void close() {
	int i;
	
	if (!openFlag)
	    return;
	if (receiver != null)
	    receiver.close();
	if (transmitter != null)
	    transmitter.close();
	
	setOpenFlag(false);
    }

    /**
     * Set the open flag explicitly. This is called by
     * CoreMidiTransmitter/CoreMidiReceiver if the device is instructed to
     * close by the person calling the library.
     */
    public void setOpenFlag(boolean _openFlag) {
	if (_openFlag)
	    usStart = 0L;
	openFlag = _openFlag;
    }

    static class Info extends MidiDevice.Info {
	protected Info(String name) {
	    super(name, "asdasd", "asd" , "0.1");
	}
    }
}