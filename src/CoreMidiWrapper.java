/*
 * CoreMidiWrapper.java: probes CoreMIDI system for all current MIDI devices
 * on the system. 
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
import javax.sound.midi.spi.MidiDeviceProvider;
import java.util.*;

/**
 * CoreMidiWrapper is the simplest of the four Java classes defined in
 * mjwrapper. Its purpose is to simply find a listing of the currently
 * available ports on the CoreMIDI system, which it does by use of a simple
 * native function.
 */
public class CoreMidiWrapper extends MidiDeviceProvider {
    private List<MidiDevice> deviceList;

    /**
     * Class constructor. On instantiation, we should load the mjwrapper
     * library, and then call initMIDIDevices() to set up the MIDI device
     * list.
     */
    public CoreMidiWrapper() {
	int i;

	deviceList = new ArrayList<MidiDevice>();

	// Load native JNI wrapper.
	System.loadLibrary("mjwrapper");

	// Call initialisation function. This will populate deviceList with
	// the current MIDI devices on the system.
	initMIDIDevices();
    }
    
    // ---------------------------------------------------------
    // Native functions
    // ---------------------------------------------------------

    /**
     * Initialise MIDI devices. This function finds all currently open sources
     * and destinations on the system. It then calls the addMIDIDevice
     * function for each source or destination it finds.
     */
    private native void initMIDIDevices();
    
    // ---------------------------------------------------------
    // MidiDeviceProvider implementation
    // ---------------------------------------------------------

    /**
     * Return the appropriate device as specified by req.
     */
    public MidiDevice getDevice(MidiDevice.Info req) {
	int i;
	
	for (i = 0; i < deviceList.size(); i++) {
	    MidiDevice dev = deviceList.get(i);
	    if (dev.getDeviceInfo().equals(req))
		return dev;
	}
	
	return null;
    }

    /**
     * Get an array of all devices; basically all available CoreMIDI devices.
     */
    public MidiDevice.Info[] getDeviceInfo() {
	int               length  = deviceList.size(), i;
	MidiDevice.Info[] devInfo = new MidiDevice.Info[length];
	
	for (i = 0; i < length; i++)
	    devInfo[i] = deviceList.get(i).getDeviceInfo();
	
	return devInfo;
    }

    /**
     * See if the device represented by info is supported. In our case, we
     * check against the list of devices and return true or false.
     */
    public boolean isDeviceSupported(MidiDevice.Info info) {
	return !(getDevice(info) == null);
    }
    
    // ---------------------------------------------------------
    // Private helper functions.
    // ---------------------------------------------------------
    
    /**
     * This is called from initMIDIDevices() inside the native library when a
     * new MIDI device is found. We create a new CoreMidiDevice and add it to
     * the list.
     */
    private void addMIDIDevice(int uniqueID) {
	deviceList.add(new CoreMidiDevice(uniqueID));
    }
}