try:
    from xml.etree import cElementTree as ET
except ImportError as e:
    from xml.etree import ElementTree as ET

roadtypes = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
             'unclassified', 'residential', 'minor', 'service'
             }

def roadp(element):
    if element.tag == 'way':
        for item in element:
            if (item.tag == 'tag' and item.attrib['k']=="highway"):
                return item.attrib['v'] in roadtypes
    return False

def namep(element):
    if element.tag == 'way':
        for item in element:
            if (item.tag == 'tag' and item.attrib['k']=="name" and len(item.attrib['v'])>1):
                return True
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

# Class for storing the detected crossings prior to clustering
class Crossing:
      counter = 0; # Number of crossing ways weighted with endpoints
      node = None
      ways = []
      def __init__(self, id, way1, way2):
          self.ways = []
          self.addroad(way1, id)
          self.addroad(way2, id)
      def addroad(self, way, id):
          self.ways.append(way)
          self.counter += node_increment(id, way)
      def addnode(self, node):
          self.node = node
      def lat(self):
          return self.node.attrib['lat']
      def long(self):
          # print self.node.attrib['long']
          return self.node.attrib['lon']
      def coordinate_string(self):
          return self.lat() + ',' + self.long()
      def properCrossing(self):
          return self.counter > 2
      def closeBy(self, other, e = 0.0001):
          return abs(float(self.lat()) - float(other.lat())) < e and abs(float(self.long()) - float(other.long())) < e
      def closeByCrossings(self, crossings):
          result = []
          for c in crossings:
              cr = crossings[c]
              if cr != self and self.closeBy(cr):
                  result.append(cr)
          return result         
    
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
        if roadp(child) and namep(child):
           for item in child:
               if item.tag == 'nd':
                  nd_ref = item.attrib['ref']
                  if not nd_ref in encountered:    # Encountered the first time 
                      encountered[nd_ref] = child
                  elif not nd_ref in crossings: # Encountered the second time
                      crossings[nd_ref] = Crossing(nd_ref, child, encountered[nd_ref])
                  else:                             # After the second time
                      crossings[nd_ref].addroad(child, item)
    for child in root:
        if child.tag == "node" and child.attrib['id'] in crossings:
            crossings[child.attrib['id']].addnode(child)

    # Find nodes that are shared with more than one way, which
    # might correspond to intersections

    #intersections = filter(lambda x: counter[x] > 2,  counter)
    crossings = dict(filter(lambda k: crossings[k[0]].properCrossing(), crossings.items()))

    # Extract intersection coordinates
    # You can plot the result using this url.
    # http://www.darrinward.com/lat-long/
    print(len(crossings))
    return crossings

def print_coordinates(osm):
    c = extract_intersections(osm)
    for id in c:
        print(c[id].coordinate_string())

def print_crossings(osm):
    c = extract_intersections(osm)
    for id in c:
        print(c[id].coordinate_string() + ' - ' + str(len(c[id].ways)) + '(' +str(c[id].counter) + ')')
        for w in c[id].ways:
                for t in w:
                    if t.tag == 'tag' and t.attrib['k'] == 'name':
                        print(' %r' % t.attrib['v'])
        for n in c[id].closeByCrossings(c):
            print('   %r' % n)
            for w in n.ways:
                for t in w:
                    if t.tag == 'tag' and t.attrib['k'] == 'name':
                        print('        %r' % t.attrib['v'])
        
print_coordinates("../data/otaniemi.osm")


