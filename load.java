import java.io.*;

public class load {
    public static void main(String[] args) {
	if (args.length<3||args.length>4) {
	    System.out.println("usage: load <ip> <port> <file> [load address]");
	    return;
	}

	// Parse arguments
	String ip = args[0];
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
	} catch (Exception e) {
	    e.printStackTrace();
	}

	System.out.println("Read " + data.length + " bytes.");
    }
}
