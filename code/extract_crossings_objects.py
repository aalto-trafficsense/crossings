try:
    from xml.etree import cElementTree as ET
except ImportError as e:
    from xml.etree import ElementTree as ET

import math
import copy

roadtypes = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
             'unclassified', 'residential', 'minor', 'service'
             }

def isRoad(element):
    if element.tag == 'way':
        for item in element:
            if (item.tag == 'tag' and item.attrib['k']=="highway"):
                return item.attrib['v'] in roadtypes
    return False

def wayName(way):
    if way.tag == 'way':
       for item in way:
           if item.tag == 'tag' and item.attrib['k']=="name":
              return item.attrib['v']
        
def wayHasName(element):
    n = wayName(element)
    if n != None:
        return len(n)>1
    return False

def node_increment(node_id, way):
    node_position = -1;
    index=0;
    for element in way:
        if element.tag == 'nd':
            if node_id == element.attrib['ref']:
                node_position = index
            index += 1
    if node_position == 0 or node_position == index-1:
        return 1
    else:
        return 2

def pointId(lat, lon):
    return str(math.floor(10000*lat))+str(math.floor(10000*lon))

# Class for storing the detected crossings prior to clustering
class Crossing:
      id = None
      lat = 0.0
      lon = 0.0
      ways = {}
      counter = 0; # Number of crossing ways weighted with endpoints
      node = None
      fake = False # Crossing with only one road name (continuation of same road, division into two unidirectionals)
      obsoletedBy = None
      replacesCrossings = []
      def __init__(self, id, lat, lon, ways):
            self.id = id
            self.lat = lat
            self.lon = lon
            self.ways = set()
            for w in ways:
               self.addroad(w, id)
            self.fake = self.fakeCrossing()
      def addroad(self, way, id):
          self.ways.add(way)
          self.counter += node_increment(id, way)
      def addnode(self, node):
          self.node = node
          self.lat = node.attrib['lat']
          self.lon = node.attrib['lon']
      def coordinate_string(self):
          return str(self.lat) + ',' + str(self.lon)
      def properCrossing(self):
#          return self.counter > 2
#          return self.counter > 1 and not self.fakeCrossing()
          return self.counter > 1
      def closeBy(self, other, e = 0.00018):
          return abs(float(self.lat) - float(other.lat)) < e and abs(float(self.lon) - float(other.lon)) < e
      def closeByCrossings(self, crossings):
          result = []
          for c in crossings:
              cr = crossings[c]
              if cr != self and cr.obsoletedBy == None and not cr.fakeCrossing() and self.closeBy(cr):
                  result.append(cr)
          return result
      def wayNames(self):
          return set(map(wayName, self.ways))
      def printCoordinates(self, e="\n"):
          print(self.coordinate_string(), end=e)
      def printCrossing(self, crossings):
          if self.fakeCrossing():
              print("Fake crossing: ", end='')
          self.printCoordinates(e='')
          print(self.wayNames())
      def fakeCrossing(self):
          return len(self.wayNames()) == 1
      def clusterableWith(self, crossing):
          return len(self.wayNames() & crossing.wayNames()) > 1
      def clusterCrossingWith(self, crossing, crossingMap, newCrossingMap):
            print('Trying to cluster: ', end='')
            self.printCrossing(crossingMap)
            print('with the crossing: ', end='')
            crossing.printCrossing(crossingMap)
            if self.obsoletedBy == None and not self.fakeCrossing() and crossing.obsoletedBy == None and not crossing.fakeCrossing():
                lat = (float(self.lat) + float(crossing.lat)) / 2
                lon = (float(self.lon) + float(crossing.lon)) / 2
                id = pointId(lat, lon)
                c = Crossing(id, lat, lon, self.ways.union(crossing.ways))
                print('Clustering result: ', end='')
                c.printCrossing(crossingMap)
                print('--')
                newCrossingMap[id] = c
                self.obsoletedBy = c
                crossing.obsoletedBy = c
                return c
            return self
      def clusterCrossing(self, crossingMap, newCrossingMap):
            if self.obsoletedBy == None and not self.fakeCrossing():
                for n in self.closeByCrossings(crossingMap):
                    if self.clusterableWith(n):
                        c = self.clusterCrossingWith(n, crossingMap, newCrossingMap)
                        return c.clusterCrossing(crossingMap, newCrossingMap)
                    else:
                        return self

# class Waypoint (Crossing):
#       obsoletes = {}
#       # def __init__(self):
            
#       def obsoleteCrossing(c):
#            self.obsoletes.add(c)
#            c.obsoletedBy = self
#       def obsoleteCrossings(cs):
#             for c in cs:
#                   self.obsoleteCrossing(c)
                  
      
    
def extract_intersections(osm, verbose=True):
    # This function takes an osm file as an input. It then goes through each xml 
    # element and searches for nodes that are shared by two or more ways.
    # Parameter:
    # - osm: An xml file that contains OpenStreetMap's map information
    # - verbose: If true, print some outputs to terminal.
    # 
    # Ex) extract_intersections('WashingtonDC.osm')
    #
    tree = ET.parse(osm)
    root = tree.getroot()
    encountered = {} # What kind of nodes have been encountered
    crossings = {}
    for child in root:
        if isRoad(child) and wayHasName(child):
           for item in child:
               if item.tag == 'nd':
                  nd_ref = item.attrib['ref']
                  if not nd_ref in encountered:    # Encountered the first time 
                      encountered[nd_ref] = child
                  elif not nd_ref in crossings: # Encountered the second time
                      crossings[nd_ref] = Crossing(nd_ref, 0.0, 0.0, {child, encountered[nd_ref]})
                  else:                             # After the second time
                      crossings[nd_ref].addroad(child, item)
    for child in root:
        if child.tag == "node" and child.attrib['id'] in crossings:
            crossings[child.attrib['id']].addnode(child)
            
    crossings = dict(filter(lambda k: crossings[k[0]].properCrossing(), crossings.items()))

#    print(len(crossings))
    return crossings

def cluster_crossings(crossings):
    clusteredCrossings = {}
    for item in crossings.items():
        item[1].clusterCrossing(crossings, clusteredCrossings)
    return clusteredCrossings

def print_coordinates(osm):
    c = extract_intersections(osm)
    clusters = cluster_crossings(c)
    print('Crossings')
    for id in c:
          p = c[id]
          if p.obsoletedBy == None and not p.fakeCrossing():
             p.printCoordinates()
    print('Clustered crossings')
    for id in clusters:
          if clusters[id].obsoletedBy == None:
             clusters[id].printCoordinates()


def print_crossings(osm):
    c = extract_intersections(osm)
    for id in c:
        c[id].printCrossing(c)
        for n in c[id].closeByCrossings(c):
            n.printCrossing(c)
        
print_coordinates("../data/otaniemi.osm")


