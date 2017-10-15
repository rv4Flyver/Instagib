part of instagib;

double q3bsptree_trace_offset = 0.03125;

class BSPNode {
  int planeNum;
  List<int> children;
  List<int> mins;
  List<int> maxs;
  BSPNode.init( this.planeNum, this.children, this.mins, this.maxs);
  BSPNode( BinaryReader br) {
    planeNum = br.readOneSignedInt();
    children = br.readSignedInt(2);
    mins = br.readSignedInt(3);
    maxs = br.readSignedInt(3);
  }
  static List<BSPNode> parse(BinaryReader br) {
    int count = br.length~/(9*4); // 9 * int32
    List<BSPNode> nodes = new List<BSPNode>(count);
    for( int i=0;i<count;i++) {
      nodes[i] = new BSPNode(br);
    }
    return nodes;
  }
}

class Plane {
  Vector normal;
  double dist;
  Plane.init( this.normal, this.dist);
  Plane( BinaryReader br) {
    normal = new Vector.useList(br.readFloat(3));
    dist = br.readOneFloat();
  }
  static List<Plane> parse(BinaryReader br) {
    int count = br.length~/(4*4); // 9 * float32
    List<Plane> planes = new List<Plane>(count);
    for( int i=0;i<count;i++) {
      planes[i] = new Plane(br);
    }
    return planes;
  }
}

class Leaf {
  int cluster;
  int area;
  List<int> mins;
  List<int> maxs;
  int firstLeafSurface;
  int numLeafSurfaces;
  int firstLeafBrush;
  int numLeafBrushes;
  Leaf.init(this.cluster, this.area, this.mins, this.maxs, this.firstLeafSurface, this.numLeafSurfaces, this.firstLeafBrush, this.numLeafBrushes);
  Leaf( BinaryReader br) {
    cluster = br.readOneSignedInt();
    area = br.readOneSignedInt();
    mins = br.readSignedInt(3);
    maxs = br.readSignedInt(3);
    firstLeafSurface = br.readOneSignedInt();
    numLeafSurfaces = br.readOneSignedInt();
    firstLeafBrush = br.readOneSignedInt();
    numLeafBrushes = br.readOneSignedInt();
  }
  static List<Leaf> parse(BinaryReader br) {
    int count = br.length~/(12*4); // 12 * int32
    List<Leaf> leafs = new List<Leaf>(count);
    for( int i=0;i<count;i++) {
      leafs[i] = new Leaf(br);
    }
    return leafs;
  }
}

class Brush {
  int firstSide;
  int numSides;
  int shaderNum;
  Brush.init( this.firstSide, this.numSides, this.shaderNum);
  Brush( BinaryReader br) {
    firstSide = br.readOneSignedInt();
    numSides = br.readOneSignedInt();
    shaderNum = br.readOneSignedInt();
  }
  static List<Brush> parse(BinaryReader br) {
    int count = br.length~/(3*4); // 3 * int32
    List<Brush> brushes = new List<Brush>(count);
    for( int i=0;i<brushes.length;i++) {
      brushes[i] = new Brush(br);
    }
    return brushes;
  }
}

class Brushside {
  int planeNum;
  int shaderNum;
  Brushside.init(this.planeNum, this.shaderNum);
  Brushside( BinaryReader br) {
    planeNum = br.readOneSignedInt();
    shaderNum = br.readOneSignedInt();
  }
  
  static List<Brushside> parse(BinaryReader br) {
    int count = br.length~/(2*4); // 2 * int32
    List<Brushside> brushSides = new List<Brushside>(count);
    for( int i=0;i<count;i++) {
      brushSides[i] = new Brushside(br);
    }
    return brushSides;
  }
}

class Output {
  bool allSolid = false;
  bool startSolid = false;
  double fraction = 1.0;
  Vector endPos = new Vector();
  Plane plane;
}

class BSPTree {
  
  List<BSPNode> nodes;
  List<Plane> planes;
  List<Leaf> leaves;
  List<Brush> brushes;
  Int32List leafBrushes;
  List<Shader> textures;
  List<Brushside> brushSides;
  List<Surface> surfaces;

  BSPTree( this.nodes, this.planes, this.leaves, this.brushes, this.leafBrushes, this.textures, this.brushSides, this.surfaces) {
    
    //for ( int i = 0 ; i < count ; i++) {      generatePatchCollide( width, height, points );    }
    
  }
  
  void generatePatchCollide( width, height, points) {
    
  }
  
  
  Output trace( Vector start, Vector end, double radius) {
    Output output = new Output(); // TODO: use tmp
    output.endPos.set( end);
    
    traceNode( 0, 0.0, 1.0, start, end, radius, output);
    
    if( output.fraction != 1.0) { // collided with something
        for( int i = 0; i < 3; i++) {
            output.endPos[i] = start[i] + output.fraction * (end[i] - start[i]);
        }
    }
    
    return output;
  }

  void traceNode( int nodeIdx, double startFraction, double endFraction, Vector start, Vector end, double radius, Output output) {
    if( nodeIdx < 0) { // Leaf node?
      Leaf leaf = leaves[-(nodeIdx + 1)];
      for( int i = 0; i < leaf.numLeafBrushes; i++) {
        Brush brush = brushes[leafBrushes[leaf.firstLeafBrush + i]];
        var texture = textures[brush.shaderNum];
        if( brush.numSides > 0 && ((texture.contentFlags & 1) == 1)) {
          this.traceBrush( brush, start, end, radius, output);
        }
      }
      return;
    }
    
    // Tree node
    BSPNode node = nodes[nodeIdx];
    Plane plane = planes[node.planeNum];
    
    double startDist = plane.normal.dot(start) - plane.dist;
    double endDist = plane.normal.dot(end) - plane.dist;
    
    if (startDist >= radius && endDist >= radius) {
      this.traceNode(node.children[0], startFraction, endFraction, start, end, radius, output );
    } else if (startDist < -radius && endDist < -radius) {
      this.traceNode(node.children[1], startFraction, endFraction, start, end, radius, output );
    } else {
      int side;
      double fraction1, fraction2, middleFraction;
      Vector middle = new Vector();

      if (startDist < endDist) {
        side = 1; // back
        double iDist = 1 / (startDist - endDist);
        fraction1 = (startDist - radius + q3bsptree_trace_offset) * iDist;
        fraction2 = (startDist + radius + q3bsptree_trace_offset) * iDist;
      } else if (startDist > endDist) {
        side = 0; // front
        double iDist = 1 / (startDist - endDist);
        fraction1 = (startDist + radius + q3bsptree_trace_offset) * iDist;
        fraction2 = (startDist - radius - q3bsptree_trace_offset) * iDist;
      } else {
        side = 0; // front
        fraction1 = 1.0;
        fraction2 = 0.0;
      }
      
      if (fraction1 < 0) fraction1 = 0.0;
      else if (fraction1 > 1) fraction1 = 1.0;
      if (fraction2 < 0) fraction2 = 0.0;
      else if (fraction2 > 1) fraction2 = 1.0;
      
      middleFraction = startFraction + (endFraction - startFraction) * fraction1;
      
      for (int i = 0; i < 3; i++) {
        middle[i] = start[i] + fraction1 * (end[i] - start[i]);
      }
      
      this.traceNode(node.children[side], startFraction, middleFraction, start, middle, radius, output );
      
      middleFraction = startFraction + (endFraction - startFraction) * fraction2;
      
      for (int i = 0; i < 3; i++) {
        middle[i] = start[i] + fraction2 * (end[i] - start[i]);
      }
      
      this.traceNode(node.children[side==0?1:0], middleFraction, endFraction, middle, end, radius, output );
    }
  }

  void traceBrush( Brush brush, Vector start, Vector end, double radius, Output output) {
    double startFraction = -1.0;
    double endFraction = 1.0;
    bool startsOut = false;
    bool endsOut = false;
    Plane collisionPlane = null;
    
    for (int i = 0; i < brush.numSides; i++) {
        Brushside brushSide = brushSides[brush.firstSide + i];
        Plane plane = planes[brushSide.planeNum];
        
        double startDist = start.dot(plane.normal ) - (plane.dist + radius);
        double endDist = end.dot(plane.normal ) - (plane.dist + radius);

        if (startDist > 0) startsOut = true;
        if (endDist > 0) endsOut = true;

        // make sure the trace isn't completely on one side of the brush
        if (startDist > 0 && endDist > 0) { return; }
        if (startDist <= 0 && endDist <= 0) { continue; }

        if (startDist > endDist) { // line is entering into the brush
            double fraction = (startDist - q3bsptree_trace_offset) / (startDist - endDist);
            if (fraction > startFraction) {
                startFraction = fraction;
                collisionPlane = plane;
            }
        } else { // line is leaving the brush
            double fraction = (startDist + q3bsptree_trace_offset) / (startDist - endDist);
            if (fraction < endFraction)
                endFraction = fraction;
        }
    }
    
    if (startsOut == false) {
        output.startSolid = true;
        if (endsOut == false)
            output.allSolid = true;
        return;
    }

    if (startFraction < endFraction) {
        if (startFraction > -1 && startFraction < output.fraction) {
            output.plane = collisionPlane;
            if (startFraction < 0.0)
                startFraction = 0.0;
            output.fraction = startFraction;
        }
    }
    
    return;
  }
  
}



