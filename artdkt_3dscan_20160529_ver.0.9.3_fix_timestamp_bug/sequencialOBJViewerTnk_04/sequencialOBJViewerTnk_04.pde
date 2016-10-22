import java.io.*;
import java.awt.*;
import processing.opengl.*;

import saito.objloader.*;

final int MAX_RECORD_NUM = 100;

OBJModel modelList[] = new OBJModel[MAX_RECORD_NUM];

// BoundingBox is a class within OBJModel. Check docs for all it can do.
BoundingBox bbox[] = new BoundingBox[MAX_RECORD_NUM];

int frameCounter = 0;

int fileObjNum=0;

int  viewObjNum = 0;


int startRecordIndex = 2;
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
  modelList[frameCounter].draw();

/*
  noFill();
  stroke(255,0,255);
   // bbox[frameCounter].draw();

  noStroke()
  */
  frameCounter++;
  frameCounter %= (viewObjNum-2);
  
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
       
       fileObjNum++; // meshファイルの数を数える
      }
      
    }
    
  }
  
  println("fileObjNum: " + fileObjNum);
    
  viewObjNum = min(MAX_RECORD_NUM, fileObjNum);
  
  
  for(int i=0; i<viewObjNum-2; i++) {

    println("" + i  + " " + fileArray[i]);

    modelList[i] = new OBJModel(this, fileObjList[i].getAbsolutePath(), "relative", TRIANGLES);
   // modelList[i].enableDebug();
  
    modelList[i].scale(500);
    //modelList[i].translateToCenter();
    //bbox[i] = new BoundingBox(this, modelList[i]);


  }
  

}
