try:
	from xml.etree import cElementTree as ET
except ImportError, e:
	from xml.etree import ElementTree as ET

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
		if child.tag == 'way':
			for item in child:
				if item.tag == 'nd':
					nd_ref = item.attrib['ref']
					if not nd_ref in counter:
						counter[nd_ref] = 0
					counter[nd_ref] += 1
	# Find nodes that are shared with more than one way, which
	# might correspond to intersections
	intersections = filter(lambda x: counter[x] > 1,  counter)
	# Extract intersection coordinates
	# You can plot the result using this url.
	# http://www.darrinward.com/lat-long/
	intersection_coordinates = []
	for child in root:
		if child.tag == 'node' and child.attrib['id'] in intersections:
			coordinate = child.attrib['lat'] + ',' + child.attrib['lon']
			if verbose:
				print coordinate
			intersection_coordinates.append(coordinate)
	return intersection_coordinates

intersections = extract_intersections('otaniemi.osm')
