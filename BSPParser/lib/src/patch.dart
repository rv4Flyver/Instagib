part of bspparser;

const int EN_TOP = 0;
const int EN_RIGHT = 1;
const int EN_BOTTOM = 2;
const int EN_LEFT = 3;

const int SIDE_FRONT = 0;
const int SIDE_BACK = 1;
const int SIDE_ON = 2;
const int SIDE_CROSS = 3;

const double MAX_MAP_BOUNDS = 65535.0;

const double NORMAL_EPSILON = 0.0001;
const double DIST_EPSILON = 0.02;
const double SURFACE_CLIP_EPSILON = 0.125;

int totalPatchBlocks=0;
int numPlanes;
List<PatchPlane> planes = new List<PatchPlane>.generate(2048, (idx)=>new PatchPlane());

class Grid {
  int width;
  int height;
  bool wrapWidth;
  bool wrapHeight;
  List<List<Vector>> points = new List<List<Vector>>.generate(129, (idx)=> new List<Vector>.generate(129, (idx)=>new Vector())); // [width*height] MAX_GRID_SIZE = 129
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write("width: $width, height: $height, $wrapWidth, $wrapHeight\n");
    for ( int i = 0 ; i < width ; i++ ) {
      for ( int j = 0 ; j < height ; j++ ) {
        sb.write( points[i][j]);
        sb.write(',');
        //print("XXX: "+points[j*width + i].toString());
      }
      sb.write('\n');
    }
    return sb.toString();
  }
}

class Winding {
  int numpoints=0;
  List<Vector> p;

  Winding([int maxpts=4]) {
    p = new List<Vector>.generate(maxpts, (idx)=>new Vector());
  }
}

class PatchPlane {
  List<double> plane = new List<double>(4);
  int   signbits;   // signx + (signy<<1) + (signz<<2), used as lookup during collision
}
class Facet {
  int     _surfacePlane;
  int     numBorders;   // 3 or four + 6 axial bevels + 4 or 3 * 4 edge bevels
  List<int> borderPlanes = new List<int>(4+6+16);
  List<bool> borderInward = new List<bool>(4+6+16);
  List<bool> borderNoAdjust = new List<bool>(4+6+16);
  
  void set surfacePlane(int surfacePlane) {
//    if( surfacePlane<0)
      //throw new Exception(-1);
    _surfacePlane = surfacePlane;
  }
  int get surfacePlane => _surfacePlane;
}
class PatchCollide {
  List<Vector> bounds = new List<Vector>.generate(2, (idx)=>new Vector());
  int numPlanes;      // surface planes plus edge planes
  List<PatchPlane> planes = new List<PatchPlane>();
  int   numFacets;
  List<Facet> facets = new List<Facet>();
}
class Patch {
  int checkcount;       // to avoid repeated testings
  int surfaceFlags;
  int contents;
  PatchCollide pc;

  Patch(Shader shader){
    this.contents = shader.contentFlags;
    this.surfaceFlags = shader.surfaceFlags;
  }
}

PatchCollide generatePatchCollide( int width, int height, List<Vector> points) {
  assert( width > 2 && height > 2);
  assert( ((width&1)==1) && ((height & 1)==1) );
  assert ( width <= 129 && height <= 129 );
  
  Grid grid = new Grid();
  grid.width = width;
  grid.height = height;
  grid.wrapWidth = false;
  grid.wrapHeight = false;
  for ( int i = 0 ; i < width ; i++ ) {
    for ( int j = 0 ; j < height ; j++ ) {
      grid.points[i][j].set( points[j*width + i]);
    }
  }
  
  // subdivide the grid
  setGridWrapWidth( grid);
  subdivideGridColumns( grid);
  removeDegenerateColumns( grid);
  
  transposeGrid( grid );

  setGridWrapWidth( grid);
  subdivideGridColumns( grid);
  removeDegenerateColumns( grid);

  // we now have a grid of points exactly on the curve
  // the aproximate surface defined by these points will be
  // collided against
  PatchCollide pc = new PatchCollide();
      
  clearBounds( pc.bounds[0], pc.bounds[1] );
  for ( int i=0; i < grid.width; i++ ) {
    for ( int j=0; j < grid.height; j++ ) {
      addPointToBounds( grid.points[i][j], pc.bounds[0], pc.bounds[1] );
    }
  }

  totalPatchBlocks += ( grid.width - 1 ) * ( grid.height - 1 );

  // generate a bsp tree for the surface
  patchCollideFromGrid( grid, pc );

  // expand by one unit for epsilon purposes
  pc.bounds[0][0] -= 1;
  pc.bounds[0][1] -= 1;
  pc.bounds[0][2] -= 1;

  pc.bounds[1][0] += 1;
  pc.bounds[1][1] += 1;
  pc.bounds[1][2] += 1;

  return pc;
}

void patchCollideFromGrid(Grid grid, PatchCollide pc) {
  int i, j;
  Vector p1, p2, p3;
  List<List<List<int>>> gridPlanes = new List<List<List<int>>>.generate(129, (idx)=> new List<List<int>>.generate(129, (idx)=>new List<int>(2))); //[MAX_GRID_SIZE][MAX_GRID_SIZE][2];
  
  Facet facet;
  List<int> borders  = new List<int>(4);
  List<bool> noAdjust = new List<bool>(4);

  numPlanes = 0;

  // find the planes for each triangle of the grid
  for ( i = 0 ; i < grid.width - 1 ; i++ ) {
    for ( j = 0 ; j < grid.height - 1 ; j++ ) {
      p1 = grid.points[i][j];
      p2 = grid.points[i+1][j];
      p3 = grid.points[i+1][j+1];
      gridPlanes[i][j][0] = findPlane( p1, p2, p3 );

      p1 = grid.points[i+1][j+1];
      p2 = grid.points[i][j+1];
      p3 = grid.points[i][j];
      gridPlanes[i][j][1] = findPlane( p1, p2, p3 );
    }
  }

  // create the borders for each facet
  for ( i = 0 ; i < grid.width - 1 ; i++ ) {
    for ( j = 0 ; j < grid.height - 1 ; j++ ) {
       
      borders[EN_TOP] = -1;
      if ( j > 0 ) {
        borders[EN_TOP] = gridPlanes[i][j-1][1];
      } else if ( grid.wrapHeight ) {
        borders[EN_TOP] = gridPlanes[i][grid.height-2][1];
      } 
      noAdjust[EN_TOP] = ( borders[EN_TOP] == gridPlanes[i][j][0] );
      if ( borders[EN_TOP] == -1 || noAdjust[EN_TOP] ) {
        borders[EN_TOP] = edgePlaneNum( grid, gridPlanes, i, j, 0 );
      }

      borders[EN_BOTTOM] = -1;
      if ( j < grid.height - 2 ) {
        borders[EN_BOTTOM] = gridPlanes[i][j+1][0];
      } else if ( grid.wrapHeight ) {
        borders[EN_BOTTOM] = gridPlanes[i][0][0];
      }
      noAdjust[EN_BOTTOM] = ( borders[EN_BOTTOM] == gridPlanes[i][j][1] );
      if ( borders[EN_BOTTOM] == -1 || noAdjust[EN_BOTTOM] ) {
        borders[EN_BOTTOM] = edgePlaneNum( grid, gridPlanes, i, j, 2 );
      }

      borders[EN_LEFT] = -1;
      if ( i > 0 ) {
        borders[EN_LEFT] = gridPlanes[i-1][j][0];
      } else if ( grid.wrapWidth ) {
        borders[EN_LEFT] = gridPlanes[grid.width-2][j][0];
      }
      noAdjust[EN_LEFT] = ( borders[EN_LEFT] == gridPlanes[i][j][1] );
      if ( borders[EN_LEFT] == -1 || noAdjust[EN_LEFT] ) {
        borders[EN_LEFT] = edgePlaneNum( grid, gridPlanes, i, j, 3 );
      }

      borders[EN_RIGHT] = -1;
      if ( i < grid.width - 2 ) {
        borders[EN_RIGHT] = gridPlanes[i+1][j][1];
      } else if ( grid.wrapWidth ) {
        borders[EN_RIGHT] = gridPlanes[0][j][1];
      }
      noAdjust[EN_RIGHT] = ( borders[EN_RIGHT] == gridPlanes[i][j][0] );
      if ( borders[EN_RIGHT] == -1 || noAdjust[EN_RIGHT] ) {
        borders[EN_RIGHT] = edgePlaneNum( grid, gridPlanes, i, j, 1 );
      }

      assert( pc.facets.length < 1024 ); // MAX_FACETS
      pc.facets.add(facet = new Facet());

      if ( gridPlanes[i][j][0] == gridPlanes[i][j][1] ) {
        if ( gridPlanes[i][j][0] == -1 ) {
          continue;   // degenrate
        }
        facet.surfacePlane = gridPlanes[i][j][0];
        facet.numBorders = 4;
        facet.borderPlanes[0] = borders[EN_TOP];
        facet.borderNoAdjust[0] = noAdjust[EN_TOP];
        facet.borderPlanes[1] = borders[EN_RIGHT];
        facet.borderNoAdjust[1] = noAdjust[EN_RIGHT];
        facet.borderPlanes[2] = borders[EN_BOTTOM];
        facet.borderNoAdjust[2] = noAdjust[EN_BOTTOM];
        facet.borderPlanes[3] = borders[EN_LEFT];
        facet.borderNoAdjust[3] = noAdjust[EN_LEFT];
        setBorderInward( facet, grid, gridPlanes, i, j, -1 );
        if ( validateFacet( facet ) ) {
          addFacetBevels( facet );
        } else {
          pc.facets.removeLast();
        }
      } else {
        // two seperate triangles
        facet.surfacePlane = gridPlanes[i][j][0];
        facet.numBorders = 3;
        facet.borderPlanes[0] = borders[EN_TOP];
        facet.borderNoAdjust[0] = noAdjust[EN_TOP];
        facet.borderPlanes[1] = borders[EN_RIGHT];
        facet.borderNoAdjust[1] = noAdjust[EN_RIGHT];
        facet.borderPlanes[2] = gridPlanes[i][j][1];
        if ( facet.borderPlanes[2] == -1 ) {
          facet.borderPlanes[2] = borders[EN_BOTTOM];
          if ( facet.borderPlanes[2] == -1 ) {
            facet.borderPlanes[2] = edgePlaneNum( grid, gridPlanes, i, j, 4 );
          }
        }
        setBorderInward( facet, grid, gridPlanes, i, j, 0 );
        if ( validateFacet( facet ) ) {
          addFacetBevels( facet );
        } else {
          pc.facets.removeLast();
        }

        assert( pc.facets.length < 1024 ); // MAX_FACETS
        pc.facets.add(facet = new Facet());
        
        // TODO: Com_Memset( facet, 0, sizeof( *facet ) );

        facet.surfacePlane = gridPlanes[i][j][1];
        facet.numBorders = 3;
        facet.borderPlanes[0] = borders[EN_BOTTOM];
        facet.borderNoAdjust[0] = noAdjust[EN_BOTTOM];
        facet.borderPlanes[1] = borders[EN_LEFT];
        facet.borderNoAdjust[1] = noAdjust[EN_LEFT];
        facet.borderPlanes[2] = gridPlanes[i][j][0];
        if ( facet.borderPlanes[2] == -1 ) {
          facet.borderPlanes[2] = borders[EN_TOP];
          if ( facet.borderPlanes[2] == -1 ) {
            facet.borderPlanes[2] = edgePlaneNum( grid, gridPlanes, i, j, 5 );
          }
        }
        setBorderInward( facet, grid, gridPlanes, i, j, 1 );
        if ( validateFacet( facet ) ) {
          addFacetBevels( facet );
        } else {
          pc.facets.removeLast();
        }
      }
    }
  }

  // copy the results out
  pc.numPlanes = numPlanes;
  pc.numFacets = pc.facets.length;
  
  pc.planes = new List<PatchPlane>(numPlanes);
  for(int n=0;n<numPlanes;n++){
    pc.planes[n] = new PatchPlane();
    pc.planes[n].plane.setAll(0, planes[n].plane);
    pc.planes[n].signbits = planes[n].signbits;
  }
}

void addFacetBevels(Facet facet) {
  int i, j, k, l;
  int axis, dir, order;
  Wrapper<bool> flipped = new Wrapper<bool>(false);
  List<double> plane=new List<double>(4);
  List<double> newplane=new List<double>(4);
  double d;
  Winding w, w2;
  Vector mins = new Vector(), maxs = new Vector(), vec = new Vector(), vec2 = new Vector();

  VectorCopy( planes[ facet.surfacePlane ].plane, plane );

  w = BaseWindingForPlane( plane,  plane[3] );
  for ( j=0; j<facet.numBorders; j++ ) {
    if (facet.borderPlanes[j] == facet.surfacePlane) continue;
    VectorCopy( planes[ facet.borderPlanes[j] ].plane, plane );

    if ( !facet.borderInward[j] ) {
      plane[0] = -plane[0];
      plane[1] = -plane[1];
      plane[2] = -plane[2];
      plane[3] = -plane[3];
    }

    w = ChopWindingInPlace( w, plane, plane[3], 0.1 );
  }
  if ( w==null ) {
    return;
  }

  WindingBounds(w, mins, maxs);

  // add the axial planes
  order = 0;
  for ( axis = 0 ; axis < 3 ; axis++ )
  {
    for ( dir = -1 ; dir <= 1 ; dir += 2, order++ )
    {
      plane.fillRange(0, 3, 0.0);
      plane[axis] = dir.toDouble();
      if (dir == 1) {
        plane[3] = maxs[axis];
      }
      else {
        plane[3] = -mins[axis];
      }
      //if it's the surface plane
      if (planeEqual(planes[facet.surfacePlane], plane, flipped)) {
        continue;
      }
      // see if the plane is allready present
      for ( i = 0 ; i < facet.numBorders ; i++ ) {
        if (planeEqual(planes[facet.borderPlanes[i]], plane, flipped))
          break;
      }

      if ( i == facet.numBorders ) {
        if (facet.numBorders > 4 + 6 + 16)
          print("ERROR: too many bevels\n");
        facet.borderPlanes[facet.numBorders] = findPlane2(plane, flipped);
        facet.borderNoAdjust[facet.numBorders] = false;
        facet.borderInward[facet.numBorders] = flipped.value;
        facet.numBorders++;
      }
    }
  }
  //
  // add the edge bevels
  //
  // test the non-axial plane edges
  for ( j = 0 ; j < w.numpoints ; j++ )
  {
    k = (j+1)%w.numpoints;
    vec.set(w.p[j]).subtract(w.p[k]);
    //if it's a degenerate edge
    if ( VectorNormalize(vec.array) < 0.5)
      continue;
    snapVector(vec);
    for ( k = 0; k < 3 ; k++ )
      if ( vec[k] == -1 || vec[k] == 1 )
        break;  // axial
    if ( k < 3 )
      continue; // only test non-axial edges

    // try the six possible slanted axials from this edge
    for ( axis = 0 ; axis < 3 ; axis++ )
    {
      for ( dir = -1 ; dir <= 1 ; dir += 2 )
      {
        // construct a plane
        vec2.scale(0);
        vec2[axis] = dir.toDouble();
        CrossProduct (vec.array, vec2.array, plane);
        if (VectorNormalize (plane) < 0.5)
          continue;
        plane[3] = DotProduct (w.p[j].array, plane);

        // if all the points of the facet winding are
        // behind this plane, it is a proper edge bevel
        for ( l = 0 ; l < w.numpoints ; l++ )
        {
          d = DotProduct (w.p[l].array, plane) - plane[3];
          if (d > 0.1)
            break;  // point in front
        }
        if ( l < w.numpoints )
          continue;

        //if it's the surface plane
        if (planeEqual(planes[facet.surfacePlane], plane, flipped)) {
          continue;
        }
        // see if the plane is allready present
        for ( i = 0 ; i < facet.numBorders ; i++ ) {
          if (planeEqual(planes[facet.borderPlanes[i]], plane, flipped)) {
              break;
          }
        }

        if ( i == facet.numBorders ) {
          if (facet.numBorders > 4 + 6 + 16)
            print("ERROR: too many bevels\n");
          facet.borderPlanes[facet.numBorders] = findPlane2(plane, flipped);

          for ( k = 0 ; k < facet.numBorders ; k++ ) {
            if (facet.borderPlanes[facet.numBorders] ==
              facet.borderPlanes[k]) print("WARNING: bevel plane already used\n");
          }

          facet.borderNoAdjust[facet.numBorders] = false;
          facet.borderInward[facet.numBorders] = flipped.value;
          //
          w2 = CopyWinding(w);
          VectorCopy(planes[facet.borderPlanes[facet.numBorders]].plane, newplane);
          if (!facet.borderInward[facet.numBorders])
          {
            newplane[0] = -newplane[0];
            newplane[1] = -newplane[1];
            newplane[2] = -newplane[2];
            newplane[3] = -newplane[3];
          } //end if
          ChopWindingInPlace( w2, newplane, newplane[3], 0.1 );
          if (w2==null) {
            print("WARNING: CM_AddFacetBevels... invalid bevel\n");
            continue;
          }
          else {
            //FreeWinding(w2);
          }
          //
          facet.numBorders++;
          //already got a bevel
//          break;
        }
      }
    }
  }
  //FreeWinding( w );

  //add opposite plane
  facet.borderPlanes[facet.numBorders] = facet.surfacePlane;
  facet.borderNoAdjust[facet.numBorders] = false;
  facet.borderInward[facet.numBorders] = true;
  facet.numBorders++;
}

Winding CopyWinding(Winding w) {
  Winding r = new Winding();
  r.numpoints = w.numpoints;
  r.p = new List<Vector>.generate(w.numpoints, (int idx)=>new Vector.fromVector(w.p[idx]));
  return r;
}

int findPlane2(List<double> plane, Wrapper<bool> flipped) {
  // see if the points are close enough to an existing plane
  for( int i=0; i<numPlanes; i++ ) {
    if (planeEqual(planes[i], plane, flipped)) return i;
  }

  // add a new plane
  assert( numPlanes < 2048 );  //  MAX_PATCH_PLANES //   Com_Error( ERR_DROP, "MAX_PATCH_PLANES" );

  VectorCopy( plane, planes[numPlanes].plane );
  planes[numPlanes].signbits = signbitsForNormal( plane );

  numPlanes++;

  flipped.value = false;

  return numPlanes-1;
}

bool validateFacet(Facet facet) {
  List<double> plane=new List<double>(4);
  int j;
  Winding w;
  List<Vector> bounds = new List<Vector>.generate(2, (idx)=>new Vector());

  if ( facet.surfacePlane == -1 ) {
    return false;
  }

  VectorCopy( planes[ facet.surfacePlane ].plane, plane );
  w = BaseWindingForPlane( plane,  plane[3] );
  for ( j = 0 ; j < facet.numBorders; j++ ) {
    if ( facet.borderPlanes[j] == -1 ) {
      return false;
    }
    VectorCopy( planes[ facet.borderPlanes[j] ].plane, plane );
    if ( !facet.borderInward[j] ) {
      plane[0] = -plane[0];
      plane[1] = -plane[1];
      plane[2] = -plane[2];
      plane[3] = -plane[3];
    }
    w = ChopWindingInPlace( w, plane, plane[3], 0.1 );
  }

  if ( w==null ) {
    return false;    // winding was completely chopped away
  }

  // see if the facet is unreasonably large
  WindingBounds( w, bounds[0], bounds[1] );
  //FreeWinding( w );
  
  for ( j = 0 ; j < 3 ; j++ ) {
    if ( bounds[1][j] - bounds[0][j] > MAX_MAP_BOUNDS ) {  
      return false;    // we must be missing a plane
    }
    if ( bounds[0][j] >= MAX_MAP_BOUNDS ) {
      return false;
    }
    if ( bounds[1][j] <= -MAX_MAP_BOUNDS ) {
      return false;
    }
  }
  return true;   // winding is fine
}

void WindingBounds(Winding w, Vector mins, Vector maxs) {

  mins[0] = mins[1] = mins[2] = MAX_MAP_BOUNDS;
  maxs[0] = maxs[1] = maxs[2] = -MAX_MAP_BOUNDS;

  for (int i=0; i<w.numpoints; i++)
  {
    for (int j=0; j<3; j++)
    {
      double v = w.p[i][j];
      if (v < mins[j])
        mins[j] = v;
      if (v > maxs[j])
        maxs[j] = v;
    }
  }
}

Winding ChopWindingInPlace(Winding inout, List<double> normal, double dist, double epsilon) {
  Winding in_;
  List<double> dists = new List<double>(64+4); // MAX_POINTS_ON_WINDING
  List<int> sides = new List<int>(64+4); // MAX_POINTS_ON_WINDING
  List<int> counts = new List<int>(3);
  double dot;
  int i, j;
  Vector p1, p2;
  Vector  mid = new Vector();
  Winding f;
  int maxpts;

  in_ = inout;
  counts[0] = counts[1] = counts[2] = 0;

// determine sides for each point
  for (i=0 ; i<in_.numpoints; i++)
  {
    dot = DotProduct (in_.p[i].array, normal);
    dot -= dist;
    dists[i] = dot;
    if (dot > epsilon)
      sides[i] = SIDE_FRONT;
    else if (dot < -epsilon)
      sides[i] = SIDE_BACK;
    else
    {
      sides[i] = SIDE_ON;
    }
    counts[sides[i]]++;
  }
  sides[i] = sides[0];
  dists[i] = dists[0];
  
  if (counts[0]==0)
  {
    return null;
  }
  if (counts[1]==0)
    return in_;   // inout stays the same

  maxpts = in_.numpoints+4; // cant use counts[0]+2 because of fp grouping errors

  f = new Winding(maxpts);
    
  for (i=0 ; i<in_.numpoints ; i++)
  {
    p1 = in_.p[i];
    
    if (sides[i] == SIDE_ON)
    {
      f.p[f.numpoints].set(p1);
      f.numpoints++;
      continue;
    }
  
    if (sides[i] == SIDE_FRONT)
    {
      f.p[f.numpoints].set(p1);
      f.numpoints++;
    }

    if (sides[i+1] == SIDE_ON || sides[i+1] == sides[i])
      continue;
      
  // generate a split point
    p2 = in_.p[(i+1)%in_.numpoints];
    
    dot = dists[i] / (dists[i]-dists[i+1]);
    for (j=0 ; j<3 ; j++)
    { // avoid round off error when possible
      if (normal[j] == 1)
        mid[j] = dist;
      else if (normal[j] == -1)
        mid[j] = -dist;
      else
        mid[j] = p1[j] + dot*(p2[j]-p1[j]);
    }
      
    f.p[f.numpoints].set(mid);
    f.numpoints++;
  }
  
  assert(f.numpoints <= maxpts);//      Com_Error (ERR_DROP, "ClipWinding: points exceeded estimate");
  assert(f.numpoints <= 64); // MAX_POINTS_ON_WINDING  //      Com_Error (ERR_DROP, "ClipWinding: MAX_POINTS_ON_WINDING");

  //FreeWinding (in_);
  inout = f;
  return f; // TODO: test this...
}


Winding BaseWindingForPlane(List<double> normal, double dist) {
  int i, x;
  double max, v;
  Vector org, vright, vup=new Vector();
  Winding w;
  
// find the major axis

  max = -MAX_MAP_BOUNDS;
  x = -1;
  for (i=0 ; i<3; i++)
  {
    v = normal[i].abs();
    if (v > max)
    {
      x = i;
      max = v;
    }
  }
  assert(x!=-1); // Com_Error (ERR_DROP, "BaseWindingForPlane: no axis found");
    
  switch (x)
  {
    case 0:
    case 1:
      vup[2] = 1.0;
      break;    
    case 2:
      vup[0] = 1.0;
      break;    
  }

  v = DotProduct (vup.array, normal);
  VectorMA (vup, -v, normal, vup);
  vup.normalize();
    
  
  org = new Vector.fromList(normal);
  
  vright = new Vector().cross2( vup, org);

  org.scale(dist);

  vup.scale( MAX_MAP_BOUNDS);
  vright.scale( MAX_MAP_BOUNDS);
      
// project a really big axis aligned box onto the plane
  w = new Winding();
  w.p[0].set(org).subtract(vright).add(vup);
  w.p[1].set(org).add(vright).add(vup);
  w.p[2].set(org).add(vright).subtract(vup);
  w.p[3].set(org).subtract(vright).subtract(vup);
  w.numpoints = 4;
  return w; 
}

void setBorderInward(Facet facet, Grid grid, List<List<List<int>>> gridPlanes, int i, int j, int which) {
  List<Vector> points = new List<Vector>.generate(4, (idx)=>new Vector());
  int numPoints;

  switch ( which ) {
  case -1:
    points[0] = grid.points[i][j];
    points[1] = grid.points[i+1][j];
    points[2] = grid.points[i+1][j+1];
    points[3] = grid.points[i][j+1];
    numPoints = 4;
    break;
  case 0:
    points[0] = grid.points[i][j];
    points[1] = grid.points[i+1][j];
    points[2] = grid.points[i+1][j+1];
    numPoints = 3;
    break;
  case 1:
    points[0] = grid.points[i+1][j+1];
    points[1] = grid.points[i][j+1];
    points[2] = grid.points[i][j];
    numPoints = 3;
    break;
  default:
    print( "setBorderInward: bad parameter" );
    numPoints = 0;
    break;
  }

  for ( int k=0; k<facet.numBorders; k++ ) {
    int front = 0;
    int back = 0;
    for ( int l=0; l<numPoints; l++ ) {
      int side = pointOnPlaneSide( points[l], facet.borderPlanes[k] );
      if ( side == SIDE_FRONT ) {
        front++;
      } if ( side == SIDE_BACK ) {
        back++;
      }
    }

    if ( front>0 && back==0 ) {
      facet.borderInward[k] = true;
    } else if ( back>0 && front==0 ) {
      facet.borderInward[k] = false;
    } else if ( front==0 && back==0 ) {
      // flat side border
      facet.borderPlanes[k] = -1;
    } else {
      // bisecting side border
      print( "WARNING: CM_SetBorderInward: mixed plane sides\n" );
      facet.borderInward[k] = false;
    }
  }
}

int pointOnPlaneSide(Vector p, int planeNum) {
  List<double> plane;
  double d;
  if ( planeNum == -1 ) {
    return SIDE_ON;
  }
  plane = planes[ planeNum ].plane;
  d = DotProduct( p.array, plane ) - plane[3];
  if ( d > 0.1 ) {
    return SIDE_FRONT;
  }
  if ( d < -0.1 ) {
    return SIDE_BACK;
  }
  return SIDE_ON;
}

int edgePlaneNum(Grid grid, List<List<List<int>>> gridPlanes, int i, int j, int k) {
  Vector p1, p2;
  Vector up = new Vector();
  int p;

  switch( k) {
    case 0: // top border
      p1 = grid.points[i][j];
      p2 = grid.points[i+1][j];
      p = gridPlane( gridPlanes, i, j, 0 );
      VectorMA( p1, 4, planes[ p ].plane, up );
      return findPlane( p1, p2, up );

    case 2: // bottom border
      p1 = grid.points[i][j+1];
      p2 = grid.points[i+1][j+1];
      p = gridPlane( gridPlanes, i, j, 1 );
      VectorMA( p1, 4, planes[ p ].plane, up );
      return findPlane( p2, p1, up );

    case 3: // left border
      p1 = grid.points[i][j];
      p2 = grid.points[i][j+1];
      p = gridPlane( gridPlanes, i, j, 1 );
      VectorMA( p1, 4, planes[ p ].plane, up );
      return findPlane( p2, p1, up );

    case 1: // right border
      p1 = grid.points[i+1][j];
      p2 = grid.points[i+1][j+1];
      p = gridPlane( gridPlanes, i, j, 0 );
      VectorMA( p1, 4, planes[ p ].plane, up );
      return findPlane( p1, p2, up );

    case 4: // diagonal out of triangle 0
      p1 = grid.points[i+1][j+1];
      p2 = grid.points[i][j];
      p = gridPlane( gridPlanes, i, j, 0 );
      VectorMA( p1, 4, planes[ p ].plane, up );
      return findPlane( p1, p2, up );

    case 5: // diagonal out of triangle 1
      p1 = grid.points[i][j];
      p2 = grid.points[i+1][j+1];
      p = gridPlane( gridPlanes, i, j, 1 );
      VectorMA( p1, 4, planes[ p ].plane, up );
      return findPlane( p1, p2, up );
  }

  print( "edgePlaneNum: bad k" );
  return -1;
}

int gridPlane(List<List<List<int>>> gridPlanes, int i, int j, int tri) {
  int p = gridPlanes[i][j][tri];
  if ( p != -1 ) {
    return p;
  }
  p = gridPlanes[i][j][tri>0?0:1];
  if ( p != -1 ) {
    return p;
  }

  // should never happen
  print( "WARNING: CM_GridPlane unresolvable\n" );
  return -1;
}

int findPlane(Vector p1, Vector p2, Vector p3) {
  List<double> plane=new List<double>(4);
  int i;
  double d;

  if ( !planeFromPoints( plane, p1, p2, p3 ) ) {
    //print("planeFromPoints $p1, $p2, $p3");
    return -1;
  }

  // see if the points are close enough to an existing plane
  for ( i = 0 ; i < numPlanes ; i++ ) {
    if ( DotProduct( plane, planes[i].plane ) < 0 ) {
      continue; // allow backwards planes?
    }

    d = DotProduct( p1.array, planes[i].plane ) - planes[i].plane[3];
    if ( d < -0.1 || d > 0.1 ) {
      continue;
    }

    d = DotProduct( p2.array, planes[i].plane ) - planes[i].plane[3];
    if ( d < -0.1 || d > 0.1 ) {
      continue;
    }

    d = DotProduct( p3.array, planes[i].plane ) - planes[i].plane[3];
    if ( d < -0.1 || d > 0.1 ) {
      continue;
    }

    // found it
    return i;
  }

  // add a new plane
  assert( numPlanes < 2048 );
  VectorCopy( plane, planes[numPlanes].plane );
  planes[numPlanes].signbits = signbitsForNormal( plane );
  numPlanes++;
  return numPlanes-1;
}

addPointToBounds( Vector v, Vector mins, Vector maxs ) {
  if ( v[0] < mins[0] ) {
    mins[0] = v[0];
  }
  if ( v[0] > maxs[0]) {
    maxs[0] = v[0];
  }

  if ( v[1] < mins[1] ) {
    mins[1] = v[1];
  }
  if ( v[1] > maxs[1]) {
    maxs[1] = v[1];
  }

  if ( v[2] < mins[2] ) {
    mins[2] = v[2];
  }
  if ( v[2] > maxs[2]) {
    maxs[2] = v[2];
  }
}

clearBounds( Vector mins, Vector maxs ) {
  mins[0] = mins[1] = mins[2] = 99999.9;
  maxs[0] = maxs[1] = maxs[2] = -99999.9;
}

void transposeGrid(Grid grid) {
  int i, j, l;
  Vector temp = new Vector();
  bool tempWrap;

  if ( grid.width > grid.height ) {
    for ( i = 0 ; i < grid.height ; i++ ) {
      for ( j = i + 1 ; j < grid.width ; j++ ) {
        if ( j < grid.height ) {
          // swap the value
          temp.set( grid.points[i][j]);
          grid.points[i][j].set( grid.points[j][i]);
          grid.points[j][i].set( temp);
        } else {
          // just copy
          grid.points[i][j].set( grid.points[j][i]);
        }
      }
    }
  } else {
    for ( i = 0 ; i < grid.width ; i++ ) {
      for ( j = i + 1 ; j < grid.height ; j++ ) {
        if ( j < grid.width ) {
          // swap the value
          temp.set( grid.points[j][i]);
          grid.points[j][i].set( grid.points[i][j]);
          grid.points[i][j].set( temp);
        } else {
          // just copy
          grid.points[j][i].set( grid.points[i][j]);
        }
      }
    }
  }

  l = grid.width;
  grid.width = grid.height;
  grid.height = l;

  tempWrap = grid.wrapWidth;
  grid.wrapWidth = grid.wrapHeight;
  grid.wrapHeight = tempWrap;
}

bool comparePoints( Vector a, Vector b ) {
  double d = a[0] - b[0];
  if ( d < -0.1 || d > 0.1 ) {
    return false;
  }
  d = a[1] - b[1];
  if ( d < -0.1 || d > 0.1 ) {
    return false;
  }
  d = a[2] - b[2];
  if ( d < -0.1 || d > 0.1 ) {
    return false;
  }
  return true;
}

void removeDegenerateColumns(Grid grid) {
  int i, j, k;
  for ( i = 0 ; i < grid.width - 1 ; i++ ) {
    for ( j = 0 ; j < grid.height ; j++ ) {
      if ( !comparePoints( grid.points[i][j], grid.points[i+1][j] ) ) {
        break;
      }
    }

    if ( j != grid.height ) {
      continue; // not degenerate
    }

    for ( j = 0 ; j < grid.height ; j++ ) {
      // remove the column
      for ( k = i + 2 ; k < grid.width ; k++ ) {
        grid.points[k-1][j].set( grid.points[k][j]);
      }
    }
    grid.width--;

    // check against the next column
    i--;
  }
}

bool needsSubdivision( Vector a, Vector b, Vector c ) {
  Vector cmid = new Vector();
  Vector lmid = new Vector();
  Vector delta = new Vector();
  double dist=0.0;
  int i=0;

  for ( i = 0 ; i < 3 ; i++ ) {
    // calculate the linear midpoint
    lmid[i] = 0.5*(a[i] + c[i]);
    // calculate the exact curve midpoint
    cmid[i] = 0.5 * ( 0.5*(a[i] + b[i]) + 0.5*(b[i] + c[i]) );
  }

  // see if the curve is far enough away from the linear mid
  delta.set(cmid).subtract(lmid);
  dist = delta.length();
  
  return dist >= 16; // SUBDIVIDE_DISTANCE // 4 // never more than this units away from curve
}


void subdivideGridColumns(Grid grid) {
  int   i, j, k;

  for ( i=0; i<grid.width-2;  ) {
    // grid.points[i][x] is an interpolating control point
    // grid.points[i+1][x] is an aproximating control point
    // grid.points[i+2][x] is an interpolating control point

    //
    // first see if we can collapse the aproximating collumn away
    //
    for ( j=0; j<grid.height; j++ ) {
      if ( needsSubdivision( grid.points[i][j], grid.points[i+1][j], grid.points[i+2][j]  ) ) {
        break;
      }
    }
    if ( j==grid.height ) {
      // all of the points were close enough to the linear midpoints
      // that we can collapse the entire column away
      for ( j = 0 ; j < grid.height ; j++ ) {
        // remove the column
        for ( k = i + 2 ; k < grid.width ; k++ ) {
          grid.points[k-1][j].set(grid.points[k][j]);
        }
      }

      grid.width--;

      // go to the next curve segment
      i++;
      continue;
    }

    //
    // we need to subdivide the curve
    //
    for ( j = 0 ; j < grid.height ; j++ ) {
      Vector prev, mid, next;

      // save the control points now
      prev = new Vector.fromVector(grid.points[i+0][j]);
      mid  = new Vector.fromVector(grid.points[i+1][j]);
      next = new Vector.fromVector(grid.points[i+2][j]);

      // make room for two additional columns in the grid
      // columns i+1 will be replaced, column i+2 will become i+4
      // i+1, i+2, and i+3 will be generated
      for ( k = grid.width - 1 ; k > i + 1 ; k-- ) {
        grid.points[k+2][j].set( grid.points[k][j]);
      }

      // generate the subdivided points
      subdivide( prev, mid, next, grid.points[i+1][j], grid.points[i+2][j], grid.points[i+3][j] );
    }

    grid.width += 2;

    // the new aproximating point at i+1 may need to be removed
    // or subdivided farther, so don't advance i
  }
}

void subdivide( Vector a, Vector b, Vector c, Vector out1, Vector out2, Vector out3 ) {
  int i;

  for( i=0; i<3; i++ ) {
    out1[i] = 0.5 * (a[i] + b[i]);
    out3[i] = 0.5 * (b[i] + c[i]);
    out2[i] = 0.5 * (out1[i] + out3[i]);
  }
}

void setGridWrapWidth(Grid grid) {
  int h, j;
  double d;

  for(h=0; h<grid.height; h++) {
    for(j=0; j<3; j++) {
    //d = grid.points[h*grid.width][j] - grid.points[h*grid.width+grid.width-1][j];
      d = grid.points[0][h][j] - grid.points[grid.width-1][h][j];
      if ( d < -0.1 || d > 0.1 ) { // WRAP_POINT_EPSILON
        break;
      }
    }
    if ( j != 3 ) {
      break;
    }
  }
  grid.wrapWidth = h==grid.height;
}

