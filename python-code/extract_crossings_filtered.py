try:
    from xml.etree import cElementTree as ET
except ImportError, e:
    from xml.etree import ElementTree as ET

roadtypes = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
             'unclassified', 'residential', 'minor', 'service'
             }

# Returns true if this way belongs to <roadtypes>    
def roadp(element):
    if element.tag == 'way':
        for item in element:
            if (item.tag == 'tag' and item.attrib['k']=="highway"):
                return item.attrib['v'] in roadtypes
    return False

# Returns true if the name length > 1
def namep(element):
    if element.tag == 'way':
        for item in element:
            if (item.tag == 'tag' and item.attrib['k']=="name" and len(item.attrib['v'])>1):
                return True
    return False

def node_increment(node, way):
    node_position = -1;
    index=0;
    for element in way:
        if element.tag == 'nd':
            if node == element:
                node_position = index
            index += 1
    if node_position == 0 or node_position == index-1:
        return 1
    else:
        return 2

    
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
    counter = {}
    for child in root:
        if roadp(child) and namep(child):
           for item in child:
               if item.tag == 'nd':
                  nd_ref = item.attrib['ref']
                  if not nd_ref in counter:
                      counter[nd_ref] = 0
                  counter[nd_ref] += node_increment(item, child)

    # Find nodes that are shared with more than one way, which
    # might correspond to intersections
    intersections = filter(lambda x: counter[x] > 2,  counter)

    # Extract intersection coordinates
    # You can plot the result using this url.
    # http://www.darrinward.com/lat-long/
    print len(intersections)
    
    intersection_coordinates = []
    for child in root:
        if child.tag == 'node' and child.attrib['id'] in intersections:
            coordinate = child.attrib['lat'] + ',' + child.attrib['lon']
            if verbose:
                print coordinate
            intersection_coordinates.append(coordinate)

    return intersection_coordinates

extract_intersections("../data/otaniemi.osm")
