import java.io.*;
import java.awt.*;
import java.util.ArrayList;
import processing.opengl.*;

import saito.objloader.*;


ArrayList<OBJModel> objArrayList = new ArrayList();

OBJModel modelList[] = new OBJModel[10];

// BoundingBox is a class within OBJModel. Check docs for all it can do.
BoundingBox bbox[] = new BoundingBox[100];

int frameCounter = 0;

int fileObjNum=0;

int maxRecordNum = 100;
int startRecordIndex = 3;
int index;

void setup() {
  
  size(1200, 700, OPENGL);
  // The file "bot.svg" must be in the data folder
  // of the current sketch to load successfully
  index = startRecordIndex;
  
  selectFolder("Select a folder to process:", "fileSelected");
  


//  bbox = new BoundingBox(this, modelList[i]);
}

void draw() {
  
  if (fileObjNum == 0) {
    return;
  }

  background(192,224,255);
  lights();

  translate(width/2, height/2, 0);
  //rotateX(radians(frameCount)/2);
  rotateX(mouseY/100.0);
  rotateY(mouseX/100.0);


  noStroke();
  objArrayList[frameCounter].draw();

/*
  noFill();
  stroke(255,0,255);
   // bbox[frameCounter].draw();

  noStroke()
  */
  frameCounter++;
  frameCounter %= (fileObjNum/10);
  
  //println(frameCounter);
}


void fileSelected(File selection) {
  
  int meshObjFileNum = 0;
  
  if (selection == null) {
    println("Window was closed or the user hit cancel.");
  } else {
    println("User selected " + selection.getAbsolutePath());
  }
  
  String[] fileArray = selection.list();
  File[] fileObjList = selection.listFiles();
  if (fileArray != null) {
    
    for(int i=0; i<fileArray.length; i++) {
      println("" + i  + " " + fileArray[i]);
      
      if (fileArray[i].substring(0, 5).equals("mesh_") ) {
       
       fileObjNum++; 
      }
      
    }
    
  }
  
  println("fileObjNum: " + fileObjNum);
  
  for(int i=0; i<fileObjNum/10; i++) {

    println("" + i  + " " + fileArray[i]);


    //numberArray = (int[])append(numberArray,1);

    objArrayList.add( new OBJModel(this, fileObjList[i].getAbsolutePath(), "relative", TRIANGLES) );
    // modelList[i].enableDebug();
  
    objArrayList[i].scale(500);
    //modelList[i].translateToCenter();
    //bbox[i] = new BoundingBox(this, modelList[i]);


  }
  

}
