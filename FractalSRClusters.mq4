/*---------------------------------------------------------------------------\
 *                                                                           |
 *                 F R A C T A L  S R  C L U S T E R S                       |
 *                                                                           |
 * FractalSRClusters is an indicator that draws support and resistance lines |
 * based on fractals which have not yet been broken and are therefore still  |
 * relevant to the price.                                                    |
 *                                                                           |
 * Clusters are derived using the density-based spatial clustering of        |
 * applications with noise (DBSCAN) algorithm and can be drawn on the        |
 * screen. These clusters use the standard deviation of the price as bounds. |
 *                                                                           |
 * If desired, alerts may be enabled to notify the user of a bullish or      |
 * bearish breakout when it occurs. Breakouts can be defined by either an    |
 * arbitrary point break or relative to the standard deviation of the price. |
 *                                                                           |
 * PARAMETERS                                                                |
 *   Main Indicator Settings                                                 |
 *     LookBack: The number of bars to look back to find fractals            |
 *     SupportColor: The color of the support lines                          |
 *     ResistanceColor: The color of the resistance lines                    |
 *     SRLineWidth: The width of the support and resistance lines            |
 *     ShowPrice: If true, displays the price on the right side of the       |
 *                window                                                     |
 *   Cluster Settings                                                        |
 *     ShowClusters: Whether custers should be calculated at all             |
 *     StdDevPeriod: The period used to derive the standard deviation of     |
 *                   the price                                               |
 *     StdDevSigma: The amount by which the standard deviation should be     |
 *                  multiplied                                               |
 *     DrawBoundsByStdDev: If true, then boundaries for cluster regions are  |
 *                         drawn based on the distance by which a cluster    |
 *                         region searches for more members; this is         |
 *                         recommended for greater timeframes                |
 *     PointDistance: The distance in points that should be used to draw     |
 *                    bounds for cluster regions; this is used if the        |
 *                    previous parameter is set to false and is recommended  |
 *                    for lower timeframes                                   |
 *     ClusterColor: The color of the cluster boundary lines                 |
 *     ClusterLineWidth: The width of the cluster region lines               |
 *   AlertSettings                                                           |
 *     AlertOnBreakout: Notify the user when there is a cluster breakout     |
 *                                                                           |
 *--------------------------------------------------------------------------*/

#property copyright   "Copyright © 2014 Dan Shea"
#property version     "1.1"
#property description "Support/Resistance levels derived from relevant fractals"
#property description "Grouped using the clustering algorithm DBSCAN"
#property description "Alert on breakouts"
#property strict

#property indicator_chart_window

extern string Comment1 = "--- Main Indicator Settings ---";
extern int LookBack = 500;
extern color SupportColor = Blue;
extern color ResistanceColor = Red;
extern int SRLineWidth = 2;
extern bool ShowPrice = false;
extern string Comment2 = "--- Cluster Settings ---";
extern bool ShowClusters = true;
extern int StdDevPeriod = 10;
extern int StdDevSigma = 1;
extern bool DrawBoundsByStdDev = false;
extern int PointDistance = 10;
extern color ClusterColor = Orange;
extern int ClusterLineWidth = 1;
extern string Comment3 = "--- Alert Settings ---";
extern bool AlertOnBreakout = true;

double ExtUpBuffer[];
datetime ExtUpTime[];
double ExtDownBuffer[];
datetime ExtDownTime[];
double SRLines[];
double lowestLow, highestHigh;
int upSize, downSize, srSize;
double sd;
int c;
int ClusterThreshold = 2;
int Cluster2DSize = 500;
int PointBreakout;
bool alerted;
datetime alertedTime;

int OnInit() {
  PointBreakout = PointDistance;
  lowestLow = 999999;
  highestHigh = -1;
  upSize = 0;
  downSize = 0;
  srSize = 0;
  alerted = false;
  alertedTime = -1;
  
  // Clear all arrays
  ArrayInitialize(ExtUpBuffer, EMPTY_VALUE);
  ArrayInitialize(ExtUpTime, EMPTY_VALUE);
  ArrayInitialize(ExtDownBuffer, EMPTY_VALUE);
  ArrayInitialize(ExtDownTime, EMPTY_VALUE);
  ArrayInitialize(SRLines, EMPTY_VALUE);
  
  return (0);
}

void OnDeinit(const int reason) {
  int objs = ObjectsTotal();
  int i;
  for (i = objs - 1; i >= 0; i--) {
    string tmp = ObjectName(i);
    if (StringFind(tmp,"SRFractals_") != -1) {
      ObjectDelete(tmp);
    }
  }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) {
  if (Time[0] > alertedTime) {
    alerted = false;
  }
  srSize = 0;
  double fractVal;
  int limit;
  int counted_bars = IndicatorCounted();
  if(counted_bars < 0) {
    return(-1);
  }
  if(counted_bars > 0) {
    counted_bars--;
  }
  if (LookBack < 0) {
    limit = Bars - counted_bars;
  }
  else {
    limit = LookBack - counted_bars;
  }
  for(int i = 0; i < limit; i++) {
    fractVal = iFractals(NULL,0,MODE_UPPER,i);
    if (fractVal != 0.0) {
      upSize++;
      ArrayResize(ExtUpBuffer,upSize);
      ArrayResize(ExtUpTime,upSize);
      ExtUpBuffer[upSize-1] = fractVal;
      ExtUpTime[upSize-1] = Time[i];
    }
    fractVal = iFractals(NULL,0,MODE_LOWER,i);
    if (fractVal != 0.0) {
      downSize++;
      ArrayResize(ExtDownBuffer,downSize);
      ArrayResize(ExtDownTime,downSize);
      ExtDownBuffer[downSize-1] = fractVal;
      ExtDownTime[downSize-1] = Time[i];
    }
  }
  ArrayResize(SRLines,srSize);
  clearLines();
  validateLines();
  drawLines();
  if (ShowClusters) {
    getClusters();
  }
  return (0);
}

void validateLines() {
  // check the upper buffer
  int i, j;
  datetime t;
  for (i = 0; i < upSize; i++) {
    t = ExtUpTime[i];
    lowestLow = getLow(t);
    for (j = 0; j < downSize; j++) {
      if (ExtDownTime[j] < t) {
        // we are now looking at the previous fractal
        if (lowestLow >= ExtDownBuffer[j]) {
          // the i'th fractal is a valid line
          srSize++;
          ArrayResize(SRLines,srSize);
          SRLines[srSize-1] = ExtUpBuffer[i];
          break;
        }
        else {
          // this is not a relevant fractal
          break;
        }
      }
    }
  }
  
  // check the lower buffer
  for (i = 0; i < downSize; i++) {
    t = ExtDownTime[i];
    highestHigh = getHigh(t);
    for (j = 0; j < upSize; j++) {
      if (ExtUpTime[j] < t) {
        // we are now looking at the previous fractal
        if (highestHigh <= ExtUpBuffer[j]) {
          // the i'th fractal is a valid line
          srSize++;
          ArrayResize(SRLines,srSize);
          SRLines[srSize-1] = ExtDownBuffer[i];
          break;
        }
        else {
          // this is not a relevant fractal
          break;
        }
      }
    }
  }
}

void clearLines() {
  int objs = ObjectsTotal();
  int i;
  for (i = objs - 1; i >= 0; i--) {
    string tmp = ObjectName(i);
    if (StringFind(tmp,"SRFractals_") != -1) {
      ObjectDelete(tmp);
    }
  }
}

void drawLines() {
  int i;
  string str;
  for (i = 0; i < srSize; i++) {
    if (SRLines[i] <= Close[0]) {
      // draw a support line
      str = StringConcatenate("SRFractals_Support_",DoubleToStr(i,0));
      drawLine(str,SRLines[i],SupportColor,SRLineWidth);
    }
    else {
      // draw a resistance line
      str = StringConcatenate("SRFractals_Resistance_",DoubleToStr(i,0));
      drawLine(str,SRLines[i],ResistanceColor,SRLineWidth);
    }
  }
}

void drawLine(string name, double price, color col, int width) {
   if (ObjectFind(name) == 0) {
     ObjectDelete(name);
   }
   if (ShowPrice) {
     ObjectCreate(name, OBJ_HLINE, 0, Time[WindowFirstVisibleBar()], price);
   }
   else {
     ObjectCreate(name, OBJ_TREND, 0, Time[WindowFirstVisibleBar()]*2, price, 0, price);
   }
   ObjectSet(name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet(name, OBJPROP_COLOR, col);
   ObjectSet(name, OBJPROP_WIDTH, width);
}

double getHigh(datetime t) {
  double high = -1;
  int i;
  for (i = 0; i < Bars; i++) {
    if (Time[i] < t) {
      // we don't care about the bars that came before or on this fractal
      break;
    }
    else if (High[i] > high) {
      high = High[i];
    }
  }
  return (high);
}

double getLow(datetime t) {
  double low = 99999;
  int i;
  for (i = 0; i < Bars; i++) {
    if (Time[i] < t) {
      // we don't care about the bars that came before or on this fractal
      break;
    }
    else if (Low[i] < low) {
      low = Low[i];
    }
  }
  return (low);
}

void getClusters() {
  sd = iStdDev(NULL,0,StdDevPeriod,0,MODE_EMA,PRICE_CLOSE,0);
  sd *= StdDevSigma;
  double cluster[][500];
  double points[];
  int visited[];
  int noise[];
  ArrayResize(points,srSize);
  ArrayResize(visited,srSize);
  ArrayResize(noise,srSize);
  ArrayResize(cluster,0);
  ArrayCopy(points,SRLines);
  ArrayInitialize(visited,0);
  ArrayInitialize(noise,0);
  c = 0;
  int i;
  for (i = 0; i < srSize; i++) {
    if (visited[i] == 0) {
      int neighbors[];
      visited[i] = 1;
      regionQuery(neighbors, points[i], sd);
      if (ArraySize(neighbors) >= ClusterThreshold) {
        ArrayResize(cluster,c+1);
        expandCluster(points[i], points, visited, neighbors, cluster, sd, noise);
        c++;
      }
      else {
        noise[i] = 1;
      }
    }
  }
  drawClusters(cluster);
  if (AlertOnBreakout) {
    alertBreakout(cluster);
  }
}

void expandCluster(double point, double &points[], int &v1[], int &neighbors[],
                   double &cluster[][], double eps, int &noise[]) {
  int clusterIndex = 0;
  cluster[c][clusterIndex] = point;
  int i, j, k;
  int neighborSize = ArraySize(neighbors);
  for (i = 0; i < neighborSize; i++) {
    if (v1[neighbors[i]] == 0) {
      v1[neighbors[i]] = 1;
      int neighborPts[];
      regionQuery(neighborPts, points[neighbors[i]], eps);
      if (ArraySize(neighborPts) >= ClusterThreshold) {
        int oldSize = ArraySize(neighbors);
        ArrayResize(neighbors,oldSize+ArraySize(neighborPts));
        int newSize = ArraySize(neighbors);
        for (j = oldSize; j < newSize; j++) {
          neighbors[j] = neighborPts[j-oldSize];
        }
        neighborSize = newSize;
      }
    }
    
    bool inCluster = false;
    for (j = 0; j < c; j++) {
      for (k = 0; k < Cluster2DSize; k++) {
        if (points[neighbors[i]] == cluster[j][k]) {
          inCluster = true;
          break;
        }
      }
      if (inCluster) {
        break;
      }
    }
    if (!inCluster) {
      for (j = 0; j < Cluster2DSize; j++) {
        if (cluster[c][j] == 0) {
          cluster[c][j] = points[neighbors[i]];
          break;
        }
      }
    }
  }
}

void regionQuery(int &arr[], double price, double eps) {
  int i;
  int count = 0;
  for (i = 0; i < srSize; i++) {
    double val = SRLines[i];
    if (val != price && val <= (price + eps) && val >= (price - eps)) {
      // this is a support/resistance line within the standard deviation
      ArrayResize(arr,count+1);
      arr[count] = i;
      count++;
    }
  }
}

void drawClusters(double &cluster[][]) {
  int i, j, count;
  double min, max, upperBound, lowerBound, sdTmp;
  for (i = 0; i < c; i++) {
    count = 0;
    min = 99999;
    max = -1;
    string cStr = DoubleToStr(i,0);
    for (j = 0; j < Cluster2DSize; j++) {
      if (cluster[i][j] == 0.0) {
        continue;
      }
      if (cluster[i][j] < min) {
        min = cluster[i][j];
      }
      if (cluster[i][j] > max) {
        max = cluster[i][j];
      }
      count++;
    }
    if (count >= ClusterThreshold) {
      if (DrawBoundsByStdDev) {
        sdTmp = iStdDev(NULL,0,StdDevPeriod,0,MODE_EMA,PRICE_CLOSE,0);
        sdTmp *= StdDevSigma;
        upperBound = max + sdTmp;
        lowerBound = min - sdTmp;
      }
      else {
        upperBound = max + (PointDistance*Point);
        lowerBound = min - (PointDistance*Point);
      }
      drawLine(StringConcatenate("SRFractals_ClusterTop_",cStr),upperBound,ClusterColor,ClusterLineWidth);
      drawLine(StringConcatenate("SRFractals_ClusterBottom_",cStr),lowerBound,ClusterColor,ClusterLineWidth);
    }
  }
}

void alertBreakout(double &cluster[][]) {
  // the closing price two bars back should have been in a cluster while the closing
  // price one bar back is not
  if (!alerted) {
    if (priceInCluster(Close[2], cluster) && !priceInCluster(Close[1], cluster)) {
      if (Close[1] > Close[2]) {
        Alert("Bullish price break from fractal cluter on ",Symbol()," ",Period());
      }
      else {
        Alert("Bearish price break from fractal cluster on ",Symbol()," ",Period());
      }
      alerted = true;
      alertedTime = Time[0];
    }
  }
}

bool priceInCluster(double price, double &cluster[][]) {
  double offset;
  if (DrawBoundsByStdDev) {
    offset = iStdDev(NULL,0,StdDevPeriod,0,MODE_EMA,PRICE_CLOSE,0) * StdDevSigma;
  }
  else {
    offset = PointBreakout*Point;
  }
  int i, j;
  double min, max;
  for (i = 0; i < c; i++) {
    min = 99999;
    max = -1;
    for (j = 0; j < Cluster2DSize; j++) {
      if (cluster[i][j] == 0.0) {
        continue;
      }
      if (cluster[i][j] < min) {
        min = cluster[i][j];
      }
      if (cluster[i][j] > max) {
        max = cluster[i][j];
      }
    }
    if (min != -1 && max != 99999 && price >= min-offset && price <= max+offset) {
      return (true);
    }
  }
  return (false);
}