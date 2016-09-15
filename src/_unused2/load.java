import java.io.*;
import java.net.*;

public class load {
    public static void main(String[] args) {
	if (args.length<3||args.length>4) {
	    System.out.println("usage: load <ip|hostname> <port> <file> [load address]");
	    return;
	}

	// Parse arguments
	String hostname = args[0];
	int port = Integer.parseInt(args[1]);
	String fileName = args[2];
	int loadAddress = -1;
	if (args.length==4) loadAddress = Integer.parseInt(args[3],16);

	// Read file into byte array
	File file = new File(fileName);
	byte[] data = new byte[(int) file.length()];
	try {
	    FileInputStream fis = new FileInputStream(file);
	    if (fis.read(data) != file.length()) {
		System.out.println("Could not read all of file. Aborting");
		return;
	    }	    
	    System.out.println("Read " + data.length + " bytes.");
	    
	    Socket clientSocket = new Socket(hostname, port);   
	    DataOutputStream outToServer 
		= new DataOutputStream(clientSocket.getOutputStream());
	    BufferedReader inFromServer 
		= new BufferedReader(new InputStreamReader(clientSocket.getInputStream()));
	    int startOffset=0;
	    if (loadAddress==-1) {
		startOffset=2;
		loadAddress = data[0]+256*data[1];
	    }
	    int stepSize=16;
	    for(int i=startOffset; i<data.length; i+=stepSize) {
		int count = stepSize;
		if (i+count>data.length) count=data.length-i;
		//	System.out.println("Sending "+count+" bytes @ offset " + i);
		// build string to send
		String toSend = "s" + String.format("%x",loadAddress + i - startOffset);
		for(int j=0;j<count;j++) {
		    toSend = toSend + String.format(" %x",data[i+j]);
		}
		toSend = toSend + "\n";
		outToServer.write(toSend.getBytes());
		// C65GS serial interface writes a similar number of bytes back to us.  Allow for this to happen.
		System.out.print(inFromServer.read());
		//		System.out.println(toSend);
	    }
	    System.out.println("Data sent to serial proxy.  It may take some time to push through.");
	    while (true) {
		System.out.print(inFromServer.read());
	    }

	} catch (Exception e) {
	    e.printStackTrace();
	}
	

    }
}
