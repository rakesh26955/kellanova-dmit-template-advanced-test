package com;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Document;
import org.w3c.dom.NodeList;

/**
 *
 * @author tsatya
 *
 */

public class CheckFilter {
        public static void main(String[] args) throws Exception {

        boolean filterCheck = false;
        CheckFilter cf = new CheckFilter();
        DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
        DocumentBuilder db = dbf.newDocumentBuilder();
        Document document = db.parse(new File(args[0]+"/META-INF/vault/filter.xml"));
        NodeList nodeList = document.getElementsByTagName("filter");
        List<String> filterString = new ArrayList<String>();
        for(int x=0,size= nodeList.getLength(); x<size; x++) {
                filterString.add(nodeList.item(x).getAttributes().getNamedItem("root").getNodeValue());
        }
        filterCheck = cf.validateFilters(filterString,args);
        if(filterCheck){
                System.out.println("1");
                System.exit(0);
        }else{
                System.out.println("0");
                System.exit(1);
        }

    }

        /**
         *
         */
        public boolean validateFilters(List<String>filterString, String[] args){

                String referenceFileLoc = "/var/lib/build/workspace/"+args[1]+"/"+args[2]+"/filter.txt";
                int filterStringLegth =  filterString.size();
                int filterMatchCount = 0;
                try {
                        for (String filterVal :  filterString){
                        BufferedReader reader = new BufferedReader(new FileReader(referenceFileLoc));
                        try {
                            String line = null;
                            while ((line = reader.readLine()) != null) {
                                if(filterVal.contains(line) && !line.equalsIgnoreCase("")){
                                        filterMatchCount++;
                                        //System.out.println(line);
                                        break;
                                }
                            }
                            reader.close();
                        }catch(IOException e){
                                System.err.println("Some issue occured in 1st try statement : "+ e.getMessage());
                                reader.close();
                                return false;
                        }
                        }
            } catch (Exception ioe) {
                System.err.println("Some issue occured in 2 st try statement  : " + ioe.getMessage());
                return false;
            }
                if(filterStringLegth == filterMatchCount){
                        return true;
                }else{
                        return false;
                }

        }


        /**
         * to be used
         * @param jarPath
         */
        public void extractJARFile(String jarPath){

                try {
                    String command = "jar -xvf "+jarPath+" META-INF/vault/filter.xml -c /tmp";
                    Process child = Runtime.getRuntime().exec(command);

                    // Get output stream to write from it
                    OutputStream out = child.getOutputStream();

                    out.write("value ".getBytes());
                    out.flush();
                    out.close();
                    child.destroy();
                } catch (IOException e) {
                        e.printStackTrace();
                }
                return;
        }
}
