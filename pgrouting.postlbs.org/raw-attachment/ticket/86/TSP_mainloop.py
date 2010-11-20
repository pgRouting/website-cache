#
# Definitions for TSP/VRP with constraints.
#
# Copyright(c) Rod Millar 2008
# email: rodj59@yahoo.com.au , rodj59@y7.com.au
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#

import pg

class plpy_class(object):
    "Emulate the plpy module functionality from PostgreSQL"
    def __init__(self,Hostname="rod1"):
	# connect to the PostgreSQL DB
	self.db = pg.DB("transdb",Hostname,5432,None,None,'transport','lost')

    def execute(self,qry):
	"Emulate the PostgreSQL plpy.execute() function"
	# ie. return a list of dictionaries for each row retrieved
	rows = self.db.query(qry)
	try:
	    drows = rows.dictresult()
	    return drows
	except:
	    #print "*** execute(%s) returns = " % qry,rows
	    return rows

    def __del__(self):
	# close the DB connection
	self.db.close()

plpy = plpy_class() # the DB interface


# Main loop
#	Python function to find a path ordering which satisfies all constraints.
#
# max_dist = maximum distance deemed to be a consistent solution
# debug =  > 0 to produce debugging output in debug_table
# search_dist = 0|1  if want to search for best distance above max_dist also
# search_lim = max no of cycles to search
# lahead = max number of options for look-ahead to consider
# ordered = 0 if you want to force search evaluation to be priority ordered
#def mainloop(tab varchar,link_tab varchar,job_tab varchar,max_dist float,debug int,search_dist int,search_lim int,lahead int,ordered int)
def mainloop(tab ,link_tab ,job_tab ,max_dist ,debug=1 ,search_dist=1 ,search_lim=35 ,lahead=10 ,ordered=0 ):
    import time
    global dbg_line,apply_changes_time,mainloop_time,non_gridlock_time,gridlock_time,FIRST_SEQ
    MS = plpy.execute("select 'now'::timestamp as time")[0]['time']
    gridlock_time  = plpy.execute("select '00:00:00'::interval as time")[0]['time']
    non_gridlock_time = plpy.execute("select '00:00:00'::interval as time")[0]['time']
    apply_changes_time  = plpy.execute("select '00:00:00'::interval as time")[0]['time']
    search_limit = search_lim
    best_dist = 2**32 # eg. start with inifinite distance as best
    
    # seq key to first destination in the path set
    FIRST_SEQ = plpy.execute("select seq from %s where job_type in ('s','S') order by time_bound asc limit 1" % tab)[0]['seq']



    def inconsistency_class(tab,link_tab,seq,max_dist):
	rows = plpy.execute("select inconsistency_class('%s','%s',%s,%f)" % \
		    (tab,link_tab,seq,max_dist))
	rows1 = plpy.execute("select * from %s where seq = %s" % (tab,seq))
	return rows[0]['inconsistency_class'],rows1[0]

    def priority_delta(cost,priority):
	"Find the prioritised value of a solution, lower values being better"
	# might need to make this return just cost when positive ??? XXX HERE
	return cost - priority

    def min_priority_link(links):
	"Select & return the path_link from the list which has the lowest priority"
	ANS = links[0]
	for link in links[1:]:
	    if link['priority'] < ANS['priority']:
		ANS = link
	return ANS

    def movement_exclusion_pre(prev,next,dest,pre=None,dest2=None):
	"""Return non-zero if the proposed movement of d to between p and n is not worthwhile.
	pre = the destination currently the predecessor of dest.
	This is called before the proposed movement has been applied."""
	# XXX HERE could return > 1 to indicate the inner loop can break ???
	if pre is None:
	    prows = plpy.execute("select prev_dest from %s where next_dest = %d and active" % \
			  (link_tab,dest['seq']))
	    if len(prows) <= 0:
		return 1 # could be the first node of the path ... but redundant from above !!

	    pre = prows[0]['prev_dest'] # existing active predecessor to dest


	if prev['job_type'] in ('s','S') and dest['pu'] == 'f':
	    return 1 # dont link a drop straight after a start-of-day destination
	if next['job_type'] in ('e','E') and ((dest2 is None and dest['pu'] == 't') or (dest2 is not None and dest2['pu'] == 't')):
	    return 1 # dont link a PU immediately before an end-of-day destination
	if pre == prev['seq']:
	    return 1 # dont link back in same position !!!

	if prev['job'] == next['job'] and next['job_type'] not in ('p','P','s','S','e','E'):
	    return 1 # we dont split non point-2-point jobs !!!
    
	if prev['job_type'] in ('e','E') and next['job_type'] in ('s','S') :
	    return 1 # we dont insert between end-of-day & start-of-next-day markers

	if prev == dest:
	    return 1 # we cannot link destination as a successor of itself !!!

	# Add test to avoid overloading HERE XXXX !!!!!!!!!! ... or in the post method

	if  dest2 is None  or dest2 is dest:
		if dest['pu'] == 'f':
		    # dest is a Drop, find its PU
		    dPU = plpy.execute("select * from %s where job = %s and pu" % (tab,dest['job']))[0]
		    if dPU['time'] > prev['time']:
			return 10 # we dont move a Drop to an earlier position than its PickUp, move PU first
		    if dest['time_bound'] <= prev['time_bound'] and prev['pu'] == 't':
			# ie. latest Drop is earlier than earliest PU for predecessor
			return 1 # constraints unsatisfiable !!! XXX HERE


		elif dest['pu'] == 't':
		    dD = plpy.execute("select * from %s where job = %s and not pu" % (tab,dest['job']))[0]
		    if dD['time'] <= prev['time']:
			return 11 # we dont move a PU to later position than its Drop, move the Drop first
		    if dest['time_bound'] >= next['time_bound'] and next['pu'] == 'f':
			# ie. earliest PU time is later than latest Drop time for next dest
			return 1 # constraints unsatisfiable !!! XXX HERE
		    # also consider loads XXX HERE ... but need to allow sequences of more than one
		    #  destinations to be moved at a time for this otherwise incomplete !!!
	
	else: # dest2 is not None
	    # need to know the set of destinations which will be moved
	    intermediates = plpy.execute("select * from following_destinations_inclusive('%s','%s',%s) where time <= '%s'::timestamp" % \
				    ('tab','link_tab',dest['seq'],dest2['time']))
	    for inter in intermediates:
		if inter['seq'] in (prev['seq'],next['seq']):
		    return 1 # cant link segment to within itself
		if inter['pu'] == 'f':
		    # inter is a Drop, find its PU
		    dPU = plpy.execute("select * from %s where job = %s and pu" % (tab,inter['job']))[0]
		    if dPU['time'] > prev['time']:
			return 1 # we dont move a Drop to an earlier position than its PickUp, move PU first
		    if inter['time_bound'] <= prev['time_bound'] and prev['pu'] == 't':
			# ie. latest Drop is earlier than earliest PU for predecessor
			return 1 # constraints unsatisfiable !!! XXX HERE
		elif inter['pu'] == 't':
		    dD = plpy.execute("select * from %s where job = %s and not pu" % (tab,inter['job']))[0]
		    if dD['time'] <= prev['time']:
			return 1 # we dont move a PU to later position than its Drop, move the Drop first
		    if inter['time_bound'] >= next['time_bound'] and next['pu'] == 'f':
			# ie. earliest PU time is later than latest Drop time for next dest
			return 1 # constraints unsatisfiable !!! XXX HERE

	return 0

    def movement_exclusion_post(p,n,d,d2=None):
	"""Return non-zero if the movement of d to between p and n is not worthwhile.
	This is called only after the movement has been applied: ie. sequence p->d->n 
	is in the current (non-committed) path"""
	
	if d['pu'] == 'f':
		# the following are tentative
		# dont move a drop to earlier than its earliest acceptable pickup ( excluded automatically???)
		dPU = plpy.execute("select * from %s where job = %s and pu" % (tab,d['job']))[0]
		if dPU['time_bound'] > d['time']:
			return 1
		# dont move a Drop to a position where its time is later than its timebound
		#  XXX HERE strengthen this XXX !!! ???
		#if d['load_pcnt'] > 1.01:
		 #   #return 1  # don't overload
		   # pass
		if d['time'] > d['time_bound'] :
			# superficially, the drop is too late
			# ... check what the direct time would be
			if d['job_type'] in ('p','P'):
			    # p2p , take time from path_link
#			    if d['time_bound'] < d['time']:
#				return 1
			    nts = plpy.execute("select '%s'::timestamp + time_int as time from %s where prev_dest = %s and next_dest = %s" % \
						(dPU['time'],link_tab,dPU['seq'],d['seq']))[0]['time']
			    if nts > d['time_bound']:
				return 1
			else:
			    assert d['job_type'] in ('h','H','f','F'),"*** Assertion error: unexpected job_type"
			    return 1 # hourly job destinations are moved in pairs
			# dont move a Drop destination to after a Pickup destination when the latest drop timebound is 
			# earlier than the earliest timebound for the destination Pickup
			oPUs = plpy.execute("select * from following_destinations('%s','%s',%s) where pu and time <= '%s'::timestamp order by time_bound desc limit 1" % \
					    (tab,link_tab,d['seq'],p['time']))
			if len(oPUs):
				oPU = oPUs[0]
				if oPU['time_bound'] > d['time_bound']:
				    return 1

	elif d['pu'] == 't':
		# the following are tentative
		# dont move a Pickup to later than its latest acceptable drop - min travel time (consider load)
		dD = plpy.execute("select * from %s where job = %s and not pu" % (tab,d['job']))[0]
		if d['time'] > dD['time_bound']:
			return 1
		  #  pass
		#if d['load_pcnt'] > 1.01:
		 #   return 1  # dont permit moves which overload (premised on multi-dest moves)
		    #pass

		# dont move a Pickup to a position where its Drop time is later than latest timebound
		# HERE ... below could be strengthened to preclude all overdue moves
		if dD['time'] > dD['time_bound'] and d['time'] < dD['time_bound']: # only applies if previously consistent ???
		    # ie. superficially, this drop is too late
		    # ... but must check what the direct time from PU would be before excluding it
		    if dD['job_type'] in ('p','P'): # other case should be filtered out elsewhere !!! XXX
			# p2p take time from path_link
			nts = plpy.execute("select '%s'::timestamp + time_int as time from %s where prev_dest = %s and next_dest = %s" % \
						(d['time'],link_tab,d['seq'],dD['seq']))[0]['time']
			if nts > dD['time_bound'] :
				return 1 # impossible for job to be on-time
		    else:
			assert dD['job_type'] in ('h','H','f','F'),"*** Assertion error: unexpected job_type"
			# NB. hourly job destinations are moved in pairs !
			if dD['time'] > dD['time_bound']:
				return 1

		# dont move a Pickup to before a drop destination when the earliest pickup timebound
		# is later than the latest timebound for the destination drop
		oDs = plpy.execute("select * from preceding_destinations('%s','%s',%s) where (not pu) and time <= '%s'::timestamp order by time_bound asc limit 1" % \
					(tab,link_tab,d['seq'],n['time']))
		if len(oDs):
		    oD = oDs[0]
		    if oD['time_bound'] < d['time_bound']:
			    return 1
	return 0

    def apply_changes(prev,next,dest,priority=None,dest2=None):
	"Move dest to between prev & next (seq nos). Return old predecessor,successor of dest"
	global apply_changes_time,dbg_line
	TS = plpy.execute("select 'now'::timestamp as time")[0]['time']
	if dest2 == dest :
	    assert dest2 is dest,"***Assertion failed, dest1 is not dest2"
	    dest2 = None

	if debug > 3:
	    dbg_line = dbg_line + 1
	    plpy.execute("insert into debug_table values ('%s',%d)" % \
		    ("Apply_changes(%d,%d,%d, time TS=%s) " % (prev,next,dest,TS ),dbg_line))

	# if dest2 is not None, means the path segment between dest & dest2(inclusive) is to be moved 
	# to between prev & next
	if dest2 is not None:
	    # moving a segment bounded by dest & dest2
	    old_links = plpy.execute("select * from path_link_deactivation_triple('%s','%s',%d,%d,%d,%d)" % (tab,link_tab,prev,next,dest,dest2))
			
	    new_links = plpy.execute("select * from path_link_activation_triple('%s','%s',%d,%d,%d,%d)"  % \
			(tab,link_tab,prev,next,dest,dest2))

	else:  # only moving a single destination
	    old_links = plpy.execute("select * from path_link_deactivation_triple('%s','%s',%d,%d,%d)" % (tab,link_tab,prev,next,dest))
			
	    new_links = plpy.execute("select * from path_link_activation_triple('%s','%s',%d,%d,%d)"  % \
			(tab,link_tab,prev,next,dest))

	assert   len(old_links) == 3 , "Error: number of old_links = %d, prev=%s,next=%s,dest=%s,dest2=%s" % (len(old_links),prev,next,dest,dest2)
	assert   len(new_links) == 3 , "Error: number of new_links = %d, prev=%s,next=%s,dest=%s,dest2=%s" % (len(new_links),prev,next,dest,dest2)
	# deactivate the old links
	min_old_pr = None
	for oidr in old_links:
	    if priority is not None:
#		plpy.execute("update %s set active = false,priority = %f where prev_dest = %s and next_dest = %s" % \
#			(link_tab,priority,oidr['prev_dest'],oidr['next_dest']))
		plpy.execute("update %s set active = false where prev_dest = %s and next_dest = %s" % (link_tab,oidr['prev_dest'],oidr['next_dest']))
		if min_old_pr is None or min_old_pr['priority'] > oidr['priority']:
		    min_old_pr = oidr

	    else:
		plpy.execute("update %s set active = false where prev_dest = %s and next_dest = %s" % (link_tab,oidr['prev_dest'],oidr['next_dest']))
	    if debug > 3:
		dbg_line = dbg_line + 1
		plpy.execute("insert into debug_table values ('%s',%d)" % ("deactivate prev=%s , next=%s, " % (oidr['prev_dest'],oidr['next_dest']),dbg_line))

	    # collect the original prev & next destination sequence nos
	    if oidr['next_dest'] == dest :
		old_prev = oidr['prev_dest']
	    elif oidr['prev_dest'] == dest :
		old_next = oidr['next_dest']
	# increment the priority of the lowest priority de-activated link 
	if min_old_pr is not None:
	    plpy.execute("update %s set priority = %s where prev_dest = %s and next_dest = %s" % \
			    (link_tab,priority,min_old_pr['prev_dest'],min_old_pr['next_dest']))
	# activate the new links
	for nidr in new_links:
	    # activate the new links
	    if debug > 3:
		dbg_line = dbg_line + 1
		plpy.execute("insert into debug_table values ('%s',%d)" % \
			("activating path_link , priority= %s,prev= %s , next = %s, # of new = %d" % (priority,nidr['prev_dest'],nidr['next_dest'],len(new_links))  ,dbg_line))
	    if 0 and priority is not None:
		plpy.execute("update %s set active = true,priority = %f where prev_dest = %s and next_dest = %s" % \
			(link_tab,priority-1,nidr['prev_dest'],nidr['next_dest']))
	    else:
		assert nidr['prev_dest'] is not None,"Exception, nidr is None"
		plpy.execute("update %s set active = true where prev_dest = %s and next_dest = %s" % \
			(link_tab,nidr['prev_dest'],nidr['next_dest']))
	
	# now propagate constraints through the newly active path

	# XXX HERE ... would be better if we knew the earliest destination which was changed !!!
	# ... but note, propagation always stops when no change found ...
	for seq_row in old_links : # + [{'oid':dest}]:
		
	    changes = plpy.execute("select * from dest_changes('%s','%s','%s',(select prev_dest from %s where prev_dest = %s and next_dest = %s))" % \
				(tab,link_tab,job_tab,link_tab,seq_row['prev_dest'],seq_row['next_dest']))
	    if debug > 3:
		dbg_line = dbg_line +1
		plpy.execute("insert into debug_table values ('%s,prev=%d,next=%d, changes = %s',%d)" % ("activating changes  from prev_dest ",seq_row['prev_dest'],seq_row['next_dest'],changes[0]['dest_changes'],dbg_line))
	# update cumulative execution time
	apply_changes_time = plpy.execute("select (('now'::timestamp - '%s'::timestamp ) + '%s'::interval) as time" % (TS,apply_changes_time))[0]['time']
	return old_prev,old_next,old_links,new_links
	
    dbg_line = 1
    plpy.execute("insert into debug_table values ('%s',%d)" % \
		    ("***At start apply_changes_time=%s) " % (apply_changes_time, ),dbg_line))
	
    best_dist_path = None
    consistent_count = 0
    if ordered ==  0 :
	incons = plpy.execute("select * from inconsistent_dests('%s','%s',%f) order by priority asc" % (tab,link_tab,max_dist))
    else:
	incons = plpy.execute("select * from %s" % tab)  # in this case just grab all regardless of inconsistency
    num_dests = len(incons) # number of destinations in the path
    if debug :
	plpy.execute("delete from debug_table") # debugging
    while  (ordered <> 0 and search_limit > 0 and consistent_count < num_dests) or ( ordered == 0 and len(incons) and search_limit > 0) :  # NB. not really necessary to identify inconsistency set in advance HERE XXX

	# keep processing until no inconsistencies remain or search limit is exceeded
	search_limit = search_limit -1
	if search_limit < 0:
	    # abort with failure, return the empty destinations list
	    return []

	# ... NB. to escape an inconsistency, priority must exceed weakest justification for it
	# , which means the priority of the active link


	# option_costs = [ [prev,next,dest,dest2,priority,cost,detect] ... ] for each candidate
	option_costs = []
	gridlocked = 1
	consistent_count = 0

	for option1 in incons:
	    # XXX HERE ... if options are not guaranteed inconsistent in advance, need to apply the test here
	    if ordered <> 0:
		flag,option = inconsistency_class(tab,link_tab,option1['seq'],max_dist)
	    else:
		option = option1
		flag = option['flag']

	    # take the alternate (ie. presently inactive) path_links & compute the cost to activate each
	    # ... which is the priority of the weakest active path_link precluding the activation
	
	    # but first decide what causes the inconsistency so the minimal option set is considered
	    if debug > 3:
		dbg_line = dbg_line+1
		dbg_line = dbg_line + 1

		plpy.execute("insert into debug_table values ('%s',%d)" % \
			(" *** for option in incons seq=%d,suburb=%s,time=%s,dist=%f,load=%f,flag=%s,pu=%s" % \
				(option['seq'],option['suburb'],option['time'],option['dist'],option['load_pcnt'],option['flag'],option['pu']),dbg_line))


	    if flag[5] == '1': # flag & 0000010 :
		# missing predecessor
		# ... this case should no longer apply since changes are applied in sets so the path remains complete
		raise "Error: missing predecessor flag detected"

	    elif flag[3] == '1': #flag & 0001000 :
		# drop before pickup
		# ... either move the drop after the pickup or the pickup before the drop
		# NB. the one processed first will necessarily have no lesser priority than the other 
		# destination of the same job !
		if debug > 1:
		    dbg_line = dbg_line + 1
		    plpy.execute("insert into debug_table values ( '*** Drop before PU, seq # = %s, job # = %s, suburb = %s , flag = %s, pu=%s',%d)" % (option['seq'],option['job'],option['suburb'], flag,option['pu'],dbg_line))
		    

		# see if we have a drop or a pickup
		if option['pu'] == 'f' :   #  XXX pg.DB returns 't' or 'f', plpy return 0 or 1 !!!
		    Drop = option
		    prows = plpy.execute("select * from %s where job = %s and pu" % (tab,option['job']))
		    PU = prows[0]
		else :
		    drows = plpy.execute("select * from %s where job = %s and not pu" % (tab,option['job']))
		    PU = option
		    Drop = drows[0]

		# find whichever has highest priority
		if Drop['priority'] > PU['priority']:
		    Detect = Drop
		else:
		    Detect = PU
		
		# now PU/Drop are pickup & drop destinations corresponding  to options job

		# try moving the Drop to a location after pickup

		# find the set of destinations which follow the Pickup
		follows =  plpy.execute("select * from following_destinations_inclusive('%s','%s',%d)" % \
				    (tab,link_tab,PU['seq']))
		    
		# the Drop must be linked as the predecessor of one of these
		option_priority = None
		temp_options = []
		temp_options_nongridlock = []
		for i in range(1,len(follows)) :
			prev = follows[i-1]
			next = follows[i]
			if prev['job'] == next['job'] and prev['job_type'] not in ('p','P','s','S'):
			    continue
			
			if movement_exclusion_pre(prev,next,Drop): continue
			
			rows = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
						(tab,link_tab,prev['seq'],next['seq'],Drop['seq']))
			# priority of moving the Drop to this location
			if rows[0]['path_link_reloc_priority'] < Detect['priority']:
			    temp_options_nongridlock.append([prev,next,Drop,Drop,Detect['priority'],rows[0]['path_link_reloc_priority'],Detect['seq']])
			elif option_priority is None : # or option_priority > rows[0]['path_link_reloc_priority']:
			    Dest = Drop
			    option_priority  = rows[0]['path_link_reloc_priority']
			    
			    temp_options = [[prev,next,Dest,Dest,Detect['priority'],option_priority,Detect['seq']]]
			#elif option_priority == rows[0]['path_link_reloc_priority']:
			else:
			    temp_options.append([prev,next,Dest,Dest,Detect['priority'],option_priority,Detect['seq']])

		# here indx is candidate index to cheapest option  in follows

		# try moving the Pickup to a location before the Drop
		
		precedes = plpy.execute("select * from preceding_destinations_inclusive('%s','%s',%d)" % \
					(tab,link_tab,Drop['seq']))  

		# the Pickup must be linked as the predecessor of one of these
		for i in range(1,len(precedes)):
			prev = precedes[i]
			next = precedes[i-1]

			if movement_exclusion_pre(prev,next,PU): continue

			rows = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
					    (tab,link_tab,prev['seq'],next['seq'],PU['seq']))

			if rows[0]['path_link_reloc_priority'] < Detect['priority']:
			    temp_options_nongridlock.append([prev,next,PU,PU,Detect['priority'],rows[0]['path_link_reloc_priority'],Detect['seq']])
			elif option_priority is None : # or option_priority > rows[0]['path_link_reloc_priority']:
			    Dest = PU
			    option_priority = rows[0]['path_link_reloc_priority']

			    temp_options = [[prev,next,Dest,Dest,Detect['priority'],option_priority,Detect['seq']]]
			#elif option_priority == rows[0]['path_link_reloc_priority'] :
			else:
			    temp_options.append([prev,next,Dest,Dest,Detect['priority'],option_priority,Detect['seq']])
			    
		if debug :
		    try:
			dbg_line = dbg_line+1
			plpy.execute("insert into debug_table values ('%s',%d)" % \
			    ("Drop b4 PU, prev=%d,next=%d,dest=%d,priority=%f,detect=%s,cost=%s" % \
				(prev['seq'],next['seq'],Dest['seq'],Detect['priority'],Detect['seq'],option_priority),dbg_line))
		    except:
			pass  # means only non-gridlock options found 

		option_costs = option_costs+ temp_options + temp_options_nongridlock 

	    elif flag[4] == '1': # flag & 0000100 :
		# pickup & drop on different days
		# ... either move the drop backward or move the pickup forward to same day

		if flag[3] == '1':
		    continue # if Drop before PU inconsistency also exists, we fix that first !

		# locate the PU & Drop
		if option['pu']  == 't':
		    PU = option
		    Drops = plpy.execute("select * from %s where not pu and job = %s limit 1" % \
				    (tab,option['job']))
		    Drop = Drops[0] 
		else:
		    Drop = option
		    PUs = plpy.execute("select * from %s where pu and job = %s limit 1" % \
				    (tab,option['job']))
		    PU = PUs[0]

		# find whichever has highest priority
		if PU['priority'] < Drop['priority']:
		    Detect = Drop
		else:
		    Detect = PU


		# find the am destination on same day as the Drop
		rows = plpy.execute("select * from preceding_destinations('%s','%s',%d) where job_type in ('s','S') limit 1" % \
				    (tab,link_tab,Drop['seq']))
		assert len(rows),"*** PU/Drop differing days but no intermediate Home destinations !\n"
		BefDrop = rows[0] # Home destination in morning before Drop

		# find the pm destination on same day as PU
		rows = plpy.execute("select * from following_destinations('%s','%s',%d) where job_type in ('e','E') limit 1" % \
				    (tab,link_tab,PU['seq']))
		assert len(rows),"*** PU/Drop differing days but no intermediate Home destinations !\n"
		AftPU = rows[0] # Home destination in afternoon after PU

		# method is to move PU to same day as drop, or drop to same day as pickup 
		

		# try moving PU to Drop day first
		# ... 
		rows1 = plpy.execute("select * from preceding_destinations_inclusive('%s','%s',%d)" % \
					(tab,link_tab,Drop['seq']))
		option_priority = None
		temp_options = []
		temp_options_nongridlock = []
		for i in range(1,len(rows1)):
		    prev = rows1[i]
		    next = rows1[i-1]

		    if movement_exclusion_pre(prev,next,PU): continue

		    # now check the priority to move PU to each position on the same day as the Drop
		    rows = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
				    (tab,link_tab,prev['seq'],next['seq'],PU['seq']))

		    if  rows[0]['path_link_reloc_priority'] < Detect['priority']:
			temp_options_nongridlock.append([prev,next,PU,PU,Detect['priority'],rows[0]['path_link_reloc_priority'],Detect['seq']])
		    elif option_priority is None : # or option_priority > rows[0]['path_link_reloc_priority']:
			option_priority = rows[0]['path_link_reloc_priority']
		    
			temp_options = [[prev,next,PU,PU,Detect['priority'],option_priority,Detect['seq']]]
			if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d) " % \
				( " ###  PU/Drop Different Days (move PU) : added option prev=%s,next=%s,dest=%s,cost=%s,priority=%s,detect=%s" % (prev['seq'],next['seq'],PU['seq'],option_priority,Detect['priority'],Detect['seq']),dbg_line))

			
		    #elif option_priority == rows[0]['path_link_reloc_priority']:
		    else:
			temp_options.append([prev,next,PU,PU,Detect['priority'],option_priority,Detect['seq']])
			if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d) " % \
				( " ###  PU/Drop Different Days (move PU) : added option prev=%s,next=%s,dest=%s,cost=%s,priority=%s,detect=%s" % (prev['seq'],next['seq'],PU['seq'],option_priority,Detect['priority'],Detect['seq']),dbg_line))

			
		    if prev['seq'] == BefDrop['seq']:
			break  # we have reached the am Home destination

		# indx is candidate index to the cheapest option in rows
		
			
		# now try moving Drop to PU day
		rows2 = plpy.execute("select * from following_destinations_inclusive('%s','%s',%d)" % \
					(tab,link_tab,PU['seq'])) 
		for i in range(1,len(rows2)):
		    prev = rows2[i-1]
		    next = rows2[i]

		    if movement_exclusion_pre(prev,next,Drop): continue

		    # now check the priority to move PU to each position on the same day as the Drop
		    rows = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
				    (tab,link_tab,prev['seq'],next['seq'],Drop['seq']))


		    if  rows[0]['path_link_reloc_priority'] < Detect['priority']:
			temp_options_nongridlock.append([prev,next,Drop,Drop,Detect['priority'],rows[0]['path_link_reloc_priority'],Detect['seq']])
		    elif option_priority is None : # or option_priority > rows[0]['path_link_reloc_priority']:
			option_priority = rows[0]['path_link_reloc_priority']

			temp_options = [[prev,next,Drop,Drop,Detect['priority'],option_priority,Detect['seq']]]
			if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d) " % \
				( " ###  PU/Drop Different Days(move Drop) : added option prev=%s,next=%s,dest=%s,cost=%s,priority=%s,detect=%s" % (prev['seq'],next['seq'],Drop['seq'],option_priority,Detect['priority'],Detect['seq']),dbg_line))

		    #elif option_priority == rows[0]['path_link_reloc_priority']:
		    else:
			temp_options.append([prev,next,Drop,Drop,Detect['priority'],option_priority,Detect['seq']])
			if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d) " % \
				( " ###  PU/Drop Different Days(move Drop) : added option prev=%s,next=%s,dest=%s,cost=%s,priority=%s,detect=%s" % (prev['seq'],next['seq'],Drop['seq'],option_priority,Detect['priority'],Detect['seq']),dbg_line))

		    if next['seq'] == AftPU['seq']:
			break  # we have reached the pm Home destination

		# indx is candidate index to the cheapest option in rows
	    
		# select whichever is the cheapest
		option_costs = option_costs + temp_options+ temp_options_nongridlock 
		

		if debug :
		    dbg_line = dbg_line+1
		    plpy.execute("insert into debug_table values ('%s',%d)" % \
			("PU & Drop on different days, prev=%s,next=%s,dest=%s,dest2=%s,priority=%s , cost=%s, detect=%s" % \
				(option_costs[-1][0]['seq'],option_costs[-1][1]['seq'],option_costs[-1][2]['seq'],option_costs[-1][3]['seq'],option_costs[-1][4],option_costs[-1][5],option_costs[-1][6]),dbg_line))

	    elif flag[1] == '1' and flag[0] != '1': # flag & 0100000 :
		# drop is too late
		# ... move the drop earlier or delete a destination before  drop ( .. or rearrange the preceding path ... thats the dilemma )

		PUs = plpy.execute("select * from %s where pu and job = %d" % \
				(tab,option['job']))
		PU = PUs[0] # PU is the corresponding Pickup
		
		# now find the destinations between the two ... [PU +1, ... ,Drop-1]
#		intermediates =  plpy.execute("select * from following_destinations('%s','%s',%d) where seq in (select seq from preceding_destinations('%s','%s',%d))" % \
#			    (tab,link_tab,PU['seq'],tab,link_tab,option['seq']))

		following = plpy.execute("select * from following_destinations_inclusive('%s','%s',%d)" % \
					    (tab,link_tab,option['seq']))

		# destinations before DROP   NB. XXX HERE can optimise this by limiting to destinations whose time is after the scheduled earliest PU time !!!
		preceding = plpy.execute("select * from preceding_destinations('%s','%s',%d)" % \
				(tab,link_tab,option['seq']))
		option_priority = None
		
		if debug > 1:
		    dbg_line = dbg_line + 1
		    plpy.execute("insert into debug_table values ('%s',%d)" % \
				    ("--- Drop too late, PU = %s, Drop = %s,  # of following = %d, # of intermediates = %d " % (PU['seq'],option['seq'],len(following),len(intermediates))  ,dbg_line))

		temp_options = []  
		temp_options_nongridlock = []
		Drop = option
		# first consider costs to move the destination to an earlier position in the path
		for i in  range(1,len(preceding)):
		    prev = preceding[i]
		    next = preceding[i-1]
		    if prev['job_type'] in ('s','S') and next['job_type'] in ('e','E'):
			continue # not between end-of-day/start-of-day
		    if next['seq'] == option['seq']:
			# dont move Drop before PU  XXX HERE
			Drop = PU # ... switch to moving PU further backwards instead XXX ???

		    if movement_exclusion_pre(prev,next,Drop): 
			continue

		    rows = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
					(tab,link_tab,prev['seq'],next['seq'],Drop['seq']))
		    if debug > 1:
			dbg_line = dbg_line + 1
			plpy.execute("insert into debug_table values ('%s',%d)" % \
				    ("--- Drop too late, to move Drop %s  to  between %s and %s, cost = %s " % (Drop['seq'],prev['seq'],next['seq'],rows[0]['path_link_reloc_priority'])  ,dbg_line))

		    if rows[0]['path_link_reloc_priority'] < option['priority']:
			temp_options_nongridlock.append([prev,next,Drop,Drop,option['priority'],option_priority,option['seq']])
		    elif option_priority is None : # or option_priority > rows[0]['path_link_reloc_priority'] :
			option_priority = rows[0]['path_link_reloc_priority']
			# questionable but necessary to enable the look-ahead to function on equal priorities
			temp_options = [[prev,next,option,option,option['priority'],option_priority,option['seq']]]
		    #elif option_priority == rows[0]['path_link_reloc_priority'] :
		    else:
			temp_options.append([prev,next,option,option,option['priority'],option_priority,option['seq']])
		# XXX HERE .. actually, the following should consider moving inter to all positions, as for dist-too-long case !!! since a sequence change might change the travel times
		# next consider costs to move a destination in the preceding path to after the drop
		for inter in preceding:
		    for j in range(1,len(following)):
			jprev1 = following[j-1]
			jnext1 = following[j]


			if inter['seq'] == jprev1['seq']: continue
			if jprev1['job_type'] in ('e','E') and jnext1['job_type'] in ('s','S'):
			    continue
			if jprev1['job_type'] not in ('p','P'): 
			    continue
			if jprev1['job'] == inter['job'] and inter['pu'] == 't':
			    continue

			if movement_exclusion_pre(jprev1,jnext1,inter): 
			    continue

			# priority to move inter(mediate) dest to after Drop
			rows = plpy.execute("select * from path_link_reloc_priority('%s','%s',%s,%s,%s)" % \
					(tab,link_tab,jprev1['seq'],jnext1['seq'],inter['seq']))

			if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d)" % \
				    ("--- Drop too late, to move Intermed %s  to  between %s  %s, cost = %s " % (inter['seq'],jprev1['seq'],jnext1['seq'],rows[0]['path_link_reloc_priority'])  ,dbg_line))

			if rows[0]['path_link_reloc_priority'] < option['priority']:
			    temp_options_nongridlock.append([jprev1,jnext1,inter,inter,option['priority'],rows[0]['path_link_reloc_priority'],option['seq']])
			elif option_priority is None : # or option_priority > rows[0]['path_link_reloc_priority']:
			    option_priority = rows[0]['path_link_reloc_priority']
			    temp_options = [[jprev1,jnext1,inter,inter,option['priority'],option_priority,option['seq']]]
			#elif option_priority == rows[0]['path_link_reloc_priority']:
			else:
			    temp_options.append([jprev1,jnext1,inter,inter,option['priority'],option_priority,option['seq']])

			if debug :
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d)" % \
				    ("--- Drop too late, to move Intermed %s  to  between %s  %s, cost = %s " % (inter['seq'],jprev1['seq'],jnext1['seq'],rows[0]['path_link_reloc_priority'])  ,dbg_line))
	
		if debug > 2:
		    for item in temp_options2:
			dbg_line = dbg_line + 1
			plpy.execute("insert into debug_table values ('%s',%d)" % \
			    ("--> temp_option2 ,p=%s, n=%s, d=%s,%s , pr=%s, c=%s, det=%s " % (item[0],item[1],item[2],item[3],item[4],item[5],item[6]), dbg_line))
	
		if len(temp_options) +  len(temp_options_nongridlock) < 1: 
#		    continue # skip this
		    raise "*** Exception : Wot!!!  Excluded all options !!!"  # this option not viable !!! XXX but why ???

		option_costs = option_costs + temp_options + temp_options_nongridlock

		if debug > 1 :
		    dbg_line = dbg_line+1
		    plpy.execute("insert into debug_table values ('%s',%d)" % \
			("Drop too late %s" % len(option_costs),dbg_line))
		    for item in option_costs:
			dbg_line = dbg_line + 1
			plpy.execute("insert into debug_table values ('%s',%d)" % \
			    ("-->  Drop too late, added option ,prev=%s, next=%s, dest=%s,dest2=%s , priority=%s, cost=%s, detection seq=%s " % (item[0],item[1],item[2],item[3],item[4],item[5,item[6]]), dbg_line))

	    elif flag[2] == '1' and option['pu'] == 't': # flag & 0010000 :
		# overloaded ..
		# first make sure we are working with the PU of the job
		if debug > 1:
		    dbg_line = dbg_line + 1
		    plpy.execute("insert into debug_table values ('%s',%d) " % \
			( " ### in Overloaded : option[pu] = %s, option[seq] = %s" % (option['pu'],option['seq']),dbg_line))

		if  option['pu'] != 't':
		    raise "Exception Error: executing overloaded with a non-PU destination option" # NB. this will be dealt with by anther jobs PU
		    # NB XXX HERE ... could alternately seek first dest in which current overload occurs ???
		else:
		    PU = option
		    prows = plpy.execute("select * from path_dest where not pu and job = %s" % option['job'])
		    Drop = prows[0]
		
		# find the PUs which precede the PU where the corresponding Drop follows the PU
		rows = plpy.execute("select * from pu_b4_drop_after('%s','%s',%d) order by time asc" % \
				    (tab,link_tab,PU['seq']))
		
		
		# NB. we assume the vehicle can carry all loads one-at-a-time
		assert len(rows),"Vehicle cannot carry the load, this should not happen !!!"


		# ... either move a preceding PU to after Drop or move a following Drop to before PU
		
		# find the set of destinations following PU (inclusive)
		follows =  plpy.execute("select * from following_destinations_inclusive('%s','%s',%d)" % \
					    (tab,link_tab,PU['seq']))

		
		# find the set of destinations preceding PU (inclusive)
		precedes = plpy.execute("select * from preceding_destinations_inclusive('%s','%s',%d)" % \
					    (tab,link_tab,PU['seq']))
		

		# try moving a preceding PU to after PU (NB. can restrict to before the PUs corresponding Drop XXX HERE)
		option_priority = None
		temp_options = []
		temp_options_nongridlock = []
		for pre_PU in rows:
		    if pre_PU['pu'] == 'f':
			continue # skip drops

		    for j in range(1,len(follows)):
			prev = follows[j-1]
			next = follows[j]

			if prev['job_type'] in ('e','E') and next['jobt_type'] in ('s','S'):
			    continue # not between end-of-day/start-of-day
#			if pre_PU['job'] == prev['job'] and pre_PU is not prev :
#			    #break
#			    pre_PU = prev  # XXX HERE ... a succinct switch here ... does it work ???
#			    #continue # dont move PU to after its corresponding Drop (XXX HERE ... this may ruin completeness !!!)
				  # ... may need to consider instead moving the Drop to after Drop, or both together

			if movement_exclusion_pre(prev,next,pre_PU):
			    continue

			rows1 = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
				    (tab,link_tab,prev['seq'],next['seq'],pre_PU['seq']))
			priority1 = rows1[0]['path_link_reloc_priority']

			if priority1 < PU['priority']:
			    temp_options_nongridlock.append([prev,next,pre_PU,pre_PU,PU['priority'],option_priority,PU['seq']])
			elif option_priority is None : # or option_priority > priority1:
			    option_priority = priority1
			    temp_options = [[prev,next,pre_PU,pre_PU,PU['priority'],priority1,PU['seq']]]
			#elif option_priority == priority1:
			else:
			    temp_options.append([prev,next,pre_PU,pre_PU,PU['priority'],priority1,PU['seq']])

		# try moving a following Drop to before PU (NB. can restrict to after the following Drops corresponding PU XXX HERE)
		for post_Drop in rows:
		    if  post_Drop['pu'] == 't':
			continue # skip Pickups

		    for j in range(1,len(precedes)):
			prev = precedes[j]
			next = precedes[j-1]
			if prev['job_type'] in ('s','S'):
				continue
#			if next['job'] == post_Drop['job']:
#				#break
#				post_Drop = next # ... see above ... XXX will this work ??? ie. switch to the PU .. to make room for moving Drop in the next action ...
#				#continue # don't go beyond the Drops PU !!! XXX

			if movement_exclusion_pre(prev,next,post_Drop):
			    continue

			rows2 = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
				    (tab,link_tab,prev['seq'],next['seq'],post_Drop['seq']))
			priority2 = rows2[0]['path_link_reloc_priority']
			
			if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d) " % \
				( " ### in Overloaded code block: second loop, prev=%s, next=%s,option_priority=%s, priority2=%s" % (prev['seq'],next['seq'],option_priority,priority2 ),dbg_line))

			if priority2 < PU['priority']:
			    temp_options_nongridlock.append([prev,next,post_Drop,post_Drop,PU['priority'],option_priority,PU['seq']])
			elif option_priority is None : # or option_priority > priority2:
			    option_priority = priority2
			    temp_options = [[prev,next,post_Drop,post_Drop,PU['priority'],option_priority,PU['seq']]]
			#elif option_priority == priority2:
			else:
			    temp_options.append([prev,next,post_Drop,post_Drop,PU['priority'],priority2,PU['seq']])
		
		# try moving the PU to after a following Drop 
		for post_Drop in rows:   # ie. PU before Drop after set
		    if post_Drop['pu'] == 't':
			continue # skip Pickups
		    if post_Drop['job_type'] in ('e','E'):
			continue # not between end-of-day/start-of-day

		    # find the seq # of destination which follows post_Drop
		    next = plpy.execute("select * from following_destinations('%s','%s',%s) limit 1" % \
			    (tab,link_tab,post_Drop['seq']))[0]

		    if debug  > 2:
			dbg_line + 1
			plpy.execute("insert into debug_table values ('%s',%d) " % \
			( " ### in Overloaded : third loop: prev = %s, next = %s, dest = %s" % (PU['seq'],post_Drop['seq'],next['next_dest']),dbg_line))
		    # HERE XXX add movement_exclusion_pre( ) call HERE !!!!!!!!!!
		    if movement_exclusion_pre(PU,post_Drop,next):
			continue
		    rows3 = plpy.execute("select * from path_link_reloc_priority('%s','%s',%s,%s,%s) " % \
				(tab,link_tab,post_Drop['seq'],next['seq'],PU['seq']))
		    
		    priority3 = rows3[0]['path_link_reloc_priority']
		    if priority3 < PU['priority']:
			temp_options_nongridlock.append([post_Drop,next,PU,PU,PU['priority'],priority3,PU['seq']])

		    elif option_priority is None :#or option_priority > priority3:
			option_priority = priority3
			temp_options = [[post_Drop,next,PU,PU,PU['priority'],option_priority,PU['seq']]]
		    #elif option_priority == priority3:
		    else:
			temp_options.append([post_Drop,next,PU,PU,PU['priority'],priority3,PU['seq']])
		# select the best option
		
		option_costs = option_costs+ temp_options + temp_options_nongridlock 
		if len(temp_options) + len(temp_options_nongridlock) <= 0:
		    continue
		if debug  :
		    dbg_line = dbg_line+1
		    plpy.execute("insert into debug_table values ('%s',%d)" % \
			("Vehicle overloaded, prev=%s,next=%s,dest=%s,dest2=%s,cost=%s, detect = %s" % \
				(option_costs[-1][0]['seq'],option_costs[-1][1]['seq'],option_costs[-1][2]['seq'],option_costs[-1][3]['seq'],option_costs[-1][5],option_costs[-1][6]),dbg_line))
	      


	    elif flag[0] == '1' : # flag & 1000000 :
		# distance too long
		# ... select an active link preceding the inconsistency detection point and deactivate it
		# or, put another way, move one of the destinations in the path prior to detection
		# .. the alternate position should preferably minimise the travel distance ... but this 
		# may take many further steps to evaluate ...

		# it is only the destinations which precede this destination which can affect distance ...
		i_precedes = plpy.execute("select * from preceding_destinations('%s','%s',%d) where inconsistency_class('%s','%s',seq,%f) & B'1000000' = B'1000000' limit 1 " % \
					    (tab,link_tab,option['seq'],tab,link_tab,max_dist ))

		# further it is only necessary to process the first destination at which distance
		# is too great !
		if len(i_precedes):
		    continue # we skip this since processing will happen at an earlier inconsistent destination
			     # NB. distance is not as high a priority as the other constraints 
		
		precedes = plpy.execute("select * from preceding_destinations_inclusive('%s','%s',%d)" % \
					    (tab,link_tab,option['seq'])) 
		
		# one of the destinations up to & including option must have its position changed
		# ... it can be moved to anywhere  but it is preferable that the distances to its
		# new predecessor/successor be less than original
		Dest = None
		# NB. must know which destination is the first in the sequence !!! XXX HERE
		others = plpy.execute("select * from following_destinations_inclusive('%s','%s',%s)"  % \
					(tab,link_tab,FIRST_SEQ))
		option_priority = None
		temp_options = []
		temp_options_nonblocking = []
		for dest in precedes:
		    # find the priority to move dest somewhere else

		    if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d)" % \
				    ("--- Dist too long, dest = %s, suburb = %s, priority = %s " % (dest['seq'],dest['suburb'],dest['priority'])  ,dbg_line))

		    if dest['job_type'] in ('s','S','e','E') :
			continue  # this is not a movable destination eg. start/end of day marker

		    prows = plpy.execute("select prev_dest from %s where next_dest = %d and active" % \
					    (link_tab,dest['seq']))
		    if len(prows) <= 0:
			continue # could be the first node of the path ... but redundant from above !!

		    pre = prows[0]['prev_dest'] # existing active predecessor to dest
		    
		    for i in range(1,len(others)):
			prev = others[i-1]
			next = others[i]
			
			flg = movement_exclusion_pre(prev,next,dest,pre)
			if flg:
			    if flg == 11:
				break # skip rest of inner loop if dest is after PU
			    continue # skip any known exclusions
			
			rows = plpy.execute("select * from path_link_reloc_priority('%s','%s',%d,%d,%d)" % \
					    (tab,link_tab,prev['seq'],next['seq'],dest['seq']))
			mpriority = rows[0]['path_link_reloc_priority'] # priority to move dest to between prev & next
			if debug > 2:
			    dbg_line = dbg_line + 1
			    plpy.execute("insert into debug_table values ('%s',%d)" % \
				    ("--- reloc priority prev=%s nest=%s dest=%s , priority=%f " % (prev['seq'],next['seq'],dest['seq'] ,mpriority)  ,dbg_line))
			if mpriority > 8e99:
			    continue  # ie. infinite priority


			if mpriority < option['priority']:
			    # collect all which cost less than priority
			    temp_options_nonblocking.append([prev,next,dest,dest,option['priority'],mpriority,option['seq']])

			elif option_priority is None : # or option_priority > mpriority :
			    option_priority = mpriority
			    temp_options = [[prev,next,dest,dest,option['priority'],option_priority,option['seq']]]

			#elif option_priority == mpriority  : # NB. collect all that cost less than priority
			else:
			    # where priorities are equal, we can favour moves which appear to 
			    # reduce distance traveled .. eg. if the distance to it from new predecessor
			    # is less than from the old predecessor

#			    # the proposed new predecessor link

			    # this distance is shorter & priority is the same,  select this instead ...
			    temp_options.append([prev,next,dest,dest,option['priority'],option_priority,option['seq']])
		
		# append the best option
		option_costs = option_costs+ temp_options + temp_options_nonblocking 
		if debug  :
		    dbg_line = dbg_line+1
		    plpy.execute("insert into debug_table values ('%s',%d)" % \
			    ("^^^ Dist too long: number of option_costs = %d" % (len(option_costs),),dbg_line))
		    dbg_line = dbg_line + 1
		if len(temp_options) + len(temp_options_nonblocking) <= 0:
		    continue

	    elif flag[6] == '1' : # flag & 0000001 :
		# missing successor
		# ... tis case should no longer apply since changes are applied in sets so the path remains complete
		raise "Error, missing successor flag detected"

	    else:
		if flag == '0000000': consistent_count = consistent_count + 1  # reset consistent destination count
		continue  # ie. this node is not inconsistent !!!
	    
        # at this point we have added an option(s) to the end of option_costs
        # ... we now see whether sufficient priority exists to rectify the inconsistency via 
        # this option
        #p,n,d,d2,priority,cost,detect = option_costs[-1]
        option_costs.sort(key=lambda x: x[5] - x[4]) # sort on ascending cost - priority x[5] - x[4]
        
        NS = plpy.execute("select 'now'::timestamp as time")[0]['time']
        best = None
  
        # record inconsistencies before any changes are made
        row00 = plpy.execute("select * from totals('%s','%s',%f)" % (tab,link_tab,max_dist))[0]
        non_dist_inconsistencies_orig  = row00['non_dist_inconsistencies']
  
        for ix in range(min(len(option_costs),lahead)): # consider at most lahead options (arbitrary limit)
	    	choice = option_costs[ix]
	    	cst = choice[5]
	    	if cst > 8e99  :
	    		#continue
	    		break  # cost is infinite , exit loop
	    	p = choice[0]
	    	n = choice[1]
	    	d = choice[2]
	    	d2 = choice[3]
	    	prty = choice[4]
	    	    
	    	if cst >= prty:
	    		continue # cost is greater than priority needed to make the change
	    	detect = choice[6]
	  
	    	# apply the changes
	    	old_prev,old_next,old_links,new_links = apply_changes(p['seq'],n['seq'],d['seq'],None,d2['seq'])
	    	# need to update fields from the p,n,d,d2 nodes
	    	choice[0] = p = plpy.execute("select * from %s where seq = %s" % (tab,p['seq']))[0]
	    	choice[1] = n = plpy.execute("select * from %s where seq = %s" % (tab,n['seq']))[0]
	    	choice[2] = d = plpy.execute("select * from %s where seq = %s" % (tab,d['seq']))[0]
	    	choice[3] = d2 = plpy.execute("select * from %s where seq = %s" % (tab,d2['seq']))[0]
	  
	    	
	  
	    	# calculate inconsistencies after change
	    	row0 = plpy.execute("select * from totals('%s','%s',%f)" % (tab,link_tab,max_dist))[0]
	    	td = row0['total_dist']
	    	tt = row0['total_time']
	    	ip = row0['inconsistent_priority']
	    	cp = row0['consistent_priority']
	    	i = row0['inconsistencies']
	    	c = row0['consistencies']
	    	non_dist_inconsistencies = row0['non_dist_inconsistencies']
	  
	    	if debug > 1:
	    		dbg_line = dbg_line + 1
	    		plpy.execute("insert into debug_table values ('%s',%d)" % \
	    		    ("--- In Move wout Gridlock, Considering option prev=%s,next=%s,dest=%s,dest2=%s,priority=%s,cost=%s,non_dist inconsistencies=%s, inconsistencies=%s,total_dist=%s,inconsistent_priority=%s" % (p['seq'],n['seq'],d['seq'],d2['seq'],prty,cst,non_dist_inconsistencies,i,td,ip),dbg_line))
	        
	    	# test if applied move violates any known exclusions
	    	#  ... multi-dest moves permit excluding all options which introduce non-distance inconsistencies
	    	#escape =  non_dist_inconsistencies > non_dist_inconsistencies_orig or movement_exclusion_post(p,n,d,d2)
	    	escape =  movement_exclusion_post(p,n,d,d2)
	  
	    	if search_dist > 0 and non_dist_inconsistencies == 0:
	    		# ... record best result with no inconsistencies other than distance ...
	    		if td < best_dist:
	    		    best_dist = td
	    		    best_dist_path = plpy.execute("select * from %s where active" % (link_tab,))
	  
	    	apply_changes(old_prev,old_next,d['seq'],None,d2['seq']) # return to initial position before the next test
	      
	    	if escape:
	    	    continue # skip excluded options
	  
	    	if best is None :
	    	    best = (td,tt,ip,cp,i,c,choice,ix)
	    	else:
	    	    # compare inconsistencies after change to previous best
	    	    if i < best[4]:
	    		# fewer inconsistencies
	    		best = (td,tt,ip,cp,i,c,choice,ix)
	    		continue
	    	    elif i == best[4] :
	    		# same inconsistencies, consider total distance
	    		if td < best[0]:
	    		    best = (td,tt,ip,cp,i,c,choice,ix)
	    		    continue
	    		elif td < (best[0] + 0.1):
	    		    # same total distance, consider total inconsistent priority
	    		    if ip < best[2]:
	    			best = (td,tt,ip,cp,i,c,choice,ix)
	    			continue
	    	if  i < 0.01 :
	    	    break   # solution found
        if best is not None:
	    	chosen = option_costs[best[-1]]
	    	priority = chosen[4]
	    	cost = chosen[5]
	    	p = chosen[0]
	    	n = chosen[1]
	    	d = chosen[2]
	    	d2 = chosen[3]
	    	if priority > cost :
	    	    gridlocked = 0
	    	    # the priority is sufficient to outweigh the cost
	    	    # the change is activated
	    	    # ... 
	    	    apply_changes(p['seq'],n['seq'],d['seq'],priority,d2['seq']) # HERE 
	  
	    	    # deactivate the existing links and adjust priority
	    	    
	    	    if debug :
	    		dbg_line = dbg_line + 1
	  
	    		# calculate inconsistencies after change
	    		row0 = plpy.execute("select * from totals('%s','%s',%f)" % (tab,link_tab,max_dist))[0]
	    		td = row0['total_dist']
	    		tt = row0['total_time']
	    		ip = row0['inconsistent_priority']
	    		cp = row0['consistent_priority']
	    		i = row0['inconsistencies']
	    		c = row0['consistencies']
	    		non_dist_inconsistencies = row0['non_dist_inconsistencies']
	    		plpy.execute("insert into debug_table values ('%s',%d)" % \
	    		    ("--- In Move wout Gridlock, Chosen IS option prev=%s,next=%s,dest=%s,dest2=%s,priority=%s,cost=%s,non_dist inconsistencies=%s, inconsistencies=%s,total_dist=%s,inconsistent_priority=%s" % (p['seq'],n['seq'],d['seq'],d2['seq'],priority,cost,non_dist_inconsistencies,i,td,ip),dbg_line))
	  
	    	    if ordered <> 0:
	    		# need to dispose of old options after a change is made
	    		option_costs = []
	    		best = None
	    	    else:
	    		continue  # exit the loop after the first successful change .. maybe not ??? XXX HERE
        non_gridlock_time = plpy.execute("select ('now'::timestamp - '%s'::timestamp) + '%s'::interval as time" % \
    			(NS,non_gridlock_time))[0]['time']
	
	
	GS = plpy.execute("select 'now'::timestamp as time")[0]['time']
	if gridlocked and ( (ordered == 0) or consistent_count < num_dests):
	    # means insufficient priority exists to remedy any of the existing inconsistencies
	    # ... must choose an inconsistent destination & increase its priority

	    # basically need to select one of the inconsistent destinations & increase its priority
	    # to exceed the cost of remedy ..
	    # ... which one to pick is arbitrary, but will select the one whose remedy cost is least

	    # remedy cost is last field in the option_costs list for each option
	    # ... can also do analysis of which introduces the least additional inconsistencies ...
	    option_costs.sort(key=lambda x: x[-2])
	    choice = option_costs[0]  # cheapest cost option
	    cost = choice[-2]
	      
	    if cost > 8e99 :
		return [] # failed to find a solution satisfying all constraints
	    # once again, this is arbitrary ...
	    # .. we implement a look-ahead and select the one of these which results in the
	    # least number of inconsistencies after application
	    best = None

	    # record inconsistencies before any changes are made
	    row00 = plpy.execute("select * from totals('%s','%s',%f)" % (tab,link_tab,max_dist))[0]
	    non_dist_inconsistencies_orig  = row00['non_dist_inconsistencies']

	    end_it = 1   # set to 0 to apply strong exclusions unless gridlock occurs
	    while  end_it < 2:
	      if end_it <> 0: end_it = 2
	      for ix in range(0,min(lahead,len(option_costs))): # consider at most 20 options (arbitrary limit)
		  choice = option_costs[ix]
		  cst = choice[-2]
		  if cst > 8e99  or cst >  (cost + 0.01) :
			break  # cost is greater than minimum, or infinite , exit loop
		  p = choice[0]
		  n = choice[1]
		  d = choice[2]
		  d2 = choice[3]
		  prty = choice[4]
		  
		  detect = choice[6]

		  # apply the changes
		  old_prev,old_next,old_links,new_links = apply_changes(p['seq'],n['seq'],d['seq'],None,d2['seq'])
		  # need to update fields from the p,n,d,d2 nodes
		  choice[0] = p = plpy.execute("select * from %s where seq = %s" % (tab,p['seq']))[0]
		  choice[1] = n = plpy.execute("select * from %s where seq = %s" % (tab,n['seq']))[0]
		  choice[2] = d = plpy.execute("select * from %s where seq = %s" % (tab,d['seq']))[0]
		  choice[3] = d2 = plpy.execute("select * from %s where seq = %s" % (tab,d2['seq']))[0]

		

		  # calculate inconsistencies after change
		  row0 = plpy.execute("select * from totals('%s','%s',%f)" % (tab,link_tab,max_dist))[0]
		  td = row0['total_dist']
		  tt = row0['total_time']
		  ip = row0['inconsistent_priority']
		  cp = row0['consistent_priority']
		  i = row0['inconsistencies']
		  c = row0['consistencies']
		  non_dist_inconsistencies = row0['non_dist_inconsistencies']
		
		  # test if applied move violates any known exclusions
		  # ... multi-dest moves permit excluding all options which introduce non-distance inconsistencies
		  if end_it < 1: # look for a move which doesn't add non-distance inconsistencies first
		      escape = non_dist_inconsistencies > non_dist_inconsistencies_orig or movement_exclusion_post(p,n,d,d2)
		  else:
		      escape = movement_exclusion_post(p,n,d,d2)


		  if search_dist > 0 and non_dist_inconsistencies == 0:
			# ... record best result with no inconsistencies other than distance ...
			if td < best_dist:
			    best_dist = td
			    best_dist_path = plpy.execute("select * from %s where active" % (link_tab,))

		  apply_changes(old_prev,old_next,d['seq'],None,d2['seq']) # return to initial position before the next test
		
		  if escape:
		      continue # skip excluded options
		    
		  if  debug > 1:
		    dbg_line = dbg_line + 1
		    plpy.execute("insert into debug_table values ('%s',%s)" % \
			    ("# of options = %s ,td=%s, tt=%s, ip = %s, cp = %s, i=%s, c= %s , choice = %s, old_prev = %s, old_next = %s" % (len(option_costs),td,tt,ip,cp,i,c,choice,old_prev,old_next),dbg_line))
		    
		  if best is None :
		    best = (td,tt,ip,cp,i,c,choice,ix)
		  else:
		    # compare inconsistencies after change to previous best
		    if i < best[4]:
			# fewer inconsistencies
			best = (td,tt,ip,cp,i,c,choice,ix)
		    elif i == best[4] :
			# same inconsistencies, consider total distance
			if td < best[0]:
			    best = (td,tt,ip,cp,i,c,choice,ix)
			elif td < (best[0] + 0.1):
			    # same total distance, consider total inconsistent priority
			    if ip < best[2]:
				best = (td,tt,ip,cp,i,c,choice,ix)
		  if  i < 0.01 :
			break   # solution found

	    # re-apply the best option
	    if len(option_costs) <= 0 or best is None:
		dbg_line = dbg_line + 1
		mainloop_time = plpy.execute("select 'now'::timestamp - '%s'::timestamp as time" % (MS))[0]['time'] 
		plpy.execute("insert into debug_table values ('%s',%d) " % \
			( " ### Exit Program: Permanent Gridlock,cum exec times: mainloop=%s apply_changes=%s ,gridlock_time=%s,non_gridlock_time=%s" % (mainloop_time,apply_changes_time,gridlock_time,non_gridlock_time ),dbg_line))
		end_it = 1 # gridlocked, so must accept some non-distance inconsistencies
		
 
	    if debug:
		dbg_line = dbg_line + 1
		plpy.execute("insert into debug_table values ('%s',%d) " % \
			( """ *** Re-apply best gridlock escape found!!! : best dist = %s,time=%s,inconcist=%s,consist=%s,inconsist pr=%s,consist pr=%s, best option = %s,%s  """ % (best[0],best[1],best[4],best[5],best[2],best[3],option_costs[best[-1]][2]['seq'],option_costs[best[-1]][3]['seq'] ),dbg_line))
	    
	    # re-apply the best option
	    apply_changes(option_costs[best[-1]][0]['seq'],option_costs[best[-1]][1]['seq'],option_costs[best[-1]][2]['seq'],None,option_costs[best[-1]][3]['seq'])

	    # fix priorities of the activated/deactivated links
	    # ... the deactivated path_links are given priority of path_dest node 
	    #       the activated path_links are given priority of path_dest - 1
	    # 		the path_dest is given priority of the cost + 1
	    # ... in this way the selected link can be overriden again once by the path_dest 
	    # without further priority increase thus enabling all options to be considered
	    
	    # increase the priority of the lowest priority deactivated link
	    cheapest_deactivated_link = min_priority_link(old_links)
	    plpy.execute("update %s set priority = %s where prev_dest = %s and next_dest = %s" % \
				(link_tab,option_costs[best[-1]][5] + 1,cheapest_deactivated_link['prev_dest'],cheapest_deactivated_link['next_dest']))

	    if debug:
		dbg_line = dbg_line + 1
		plpy.execute("insert into debug_table values ('%s',%d)" % \
			("Gridlock: update %s set priority = %f where prev/dest in (%s/%s,%s/%s,%s/%s)" % \
			(link_tab,option_costs[best[-1]][5]+1,new_links[0]['prev_dest'],new_links[0]['next_dest'],new_links[1]['prev_dest'],new_links[1]['next_dest'],new_links[2]['prev_dest'],new_links[2]['next_dest']) \
				,dbg_line))
		dbg_line = dbg_line + 1
		plpy.execute("insert into debug_table values ('%s',%d)" % \
		    ("update %s set priority = %f where ( prev_dest = %s and next_dest = %s) or (prev_dest = %s and next_dest = %s) or (prev_dest = %s and next_dest = %s)" % \

			(link_tab,option_costs[best[-1]][5],old_links[0]['prev_dest'],old_links[0]['next_dest'],old_links[1]['prev_dest'],old_links[1]['next_dest'],old_links[2]['prev_dest'],old_links[2]['next_dest']) \
				,dbg_line))

#	    # now increase its priority
	    plpy.execute("update %s set priority = %f where seq = %s" % \
			    (tab,option_costs[best[-1]][4] + 1,option_costs[best[-1]][6]))

	    
	    if debug:
		dbg_line = dbg_line + 1
		plpy.execute("insert into debug_table values ('%s',%d)" % \
			("** Gridlock: Increased priority of seq=%d to %f" % (option_costs[best[-1]][6],option_costs[best[-1]][5]),dbg_line))

	gridlock_time = plpy.execute("select ('now'::timestamp - '%s'::timestamp) + '%s'::interval as time" % ( GS,gridlock_time))[0]['time']
	
	if ordered == 0:
	    incons = plpy.execute("select * from inconsistent_dests('%s','%s',%f)" % (tab,link_tab,max_dist))
    
#    if len(incons) > 0 and search_dist > 0:
    if (ordered == 0 and len(incons) > 0 and search_dist > 0) or (ordered <> 0 and consistent_count < num_dests and search_dist > 0):
	# we have not been able to satisfy all constraints
	# ... see if we have been able to satisfy all constraints except distance
	if best_dist_path is not None:
	    # re-instate this solution before returning
	    plpy.execute("update %s set active = false" % link_tab)
	    for row in best_dist_path:
		plpy.execute("update %s set active = true where prev_dest = %s and next_dest = %s" % \
			(link_tab,row['prev_dest'],row['next_dest']) )
	    seq_rows = plpy.execute("select seq from %s" % tab)
	    # do better HERE XXX
	    for seq in seq_rows:
		plpy.execute("select * from dest_changes('%s','%s','%s',%s)" % \
			(tab,link_tab,job_tab,seq['seq']))
    dbg_line = dbg_line + 1
    mainloop_time = plpy.execute("select 'now'::timestamp - '%s'::timestamp as time" % (MS))[0]['time'] 
    now=plpy.execute("select 'now'::timestamp as time")[0]['time']
    plpy.execute("insert into debug_table values ('%s',%d) " % \
	    ( " ### END of prog, cum exec times: mainloop=%s apply_changes=%s ,gridlock_time=%s,non_gridlock_time=%s" % (mainloop_time,apply_changes_time,gridlock_time,non_gridlock_time ),dbg_line))

    # successful, return the ordered destinations list
    return plpy.execute("select * from %s order by time asc" % tab)

