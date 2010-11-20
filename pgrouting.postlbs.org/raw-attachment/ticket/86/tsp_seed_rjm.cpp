boolean tsp_seed_rjm(population *pop, entity *adam)
{
  int           i,s,tmp,j,k;
  int           *data;
  int 			Assigned[MAX_TOWNS] ;
  int			closest2,marker1;
    
  DBG("*** In tsp_seed_rjm, pop-<len_chromosomes = %i \n",pop->len_chromosomes);
  data = (int *)adam->chromosome[0];

  for (i=0; i < pop->len_chromosomes; i++) Assigned[i] = -1;  // these are the nodes assigned to the path

  for (i=0; i<pop->len_chromosomes; i++)
  {
	Assigned[i] = -1;
    if(ids[i] == source_id)   // ie find the index where index of source_id is initially stored
      s = i;
	DBG("ids[%i] = %i,  \n",i,ids[i]);
  }
  Assigned[s] = 1; // mark this vertex's index  as assigned
  data[0] = s;  // place it in the first position
  DBG("Postion 0 , index = %i, data[0] = %i\n",s,s);
  marker1 = 0;
  for ( k=1; k < pop->len_chromosomes; k++){ // loop through every sequential position in path not yet filled
  	closest2 = -1;
	for ( i=0; i < k ; i++){ // now scan every vertex in the path which could precede a new vertex eg. 0...k
  		for (j=0; j < pop->len_chromosomes; j++)  // loop through the vertices not yet in the path eg. where Assigned[j] < 0
			if ( Assigned[j] < 0 ){ // this vertex j not yet included in the path
				// find  the unassigned vertex closest to  vertex i already in the path
				if ( closest2 < 0 || marker1 < 0 || DISTANCE[i][j] < DISTANCE[marker1][closest2] ){
					closest2 = j; // j is current index of the vertex not yet in path
					marker1 = i;  // i is current index of vertex in path
					DBG("closest1 = %i,marker1 = %i\n",closest2,marker1);
				}
			}

		// closest1 now contains index of vertex closest to member marker1 of the assigned path
		DBG("marker1 = %i, closest2 = %i\n , distance between = %f",marker1,closest2,DISTANCE[data[marker1]][closest2]);
	}
	
	DBG("Finished second loop, closest2 = %i, marker1 = %i, index k = %i\n",closest2,marker1,k);
	// now closest2 contains the index of a vertex closer to a vertex in path than any other vertex not
	// already in the path is to any vertex in the path
	// shuffle the existing following entries back down the path
	for ( j = k -1; j > marker1; j-- ){
		if ( Assigned[data[j]] ){
			DBG("Shuffling data[%i] = data[%i] = %i\n",j+1,j,data[j]);
			data[j+1] = data[j];
		}
	}
	Assigned[closest2] = 1; // mark the vertex as in the path
	data[k] = closest2;		// add the vertex into path as successor to vertex it's closest to
	DBG("data[%i] = %i\n",k,closest2);

	} // this loop fills consecutive positions in the path
   
  return TRUE;
}

