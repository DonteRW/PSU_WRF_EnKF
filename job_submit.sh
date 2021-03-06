#!/bin/bash
#HOSTTYPE, HOSTPPN are defined in config file
#JOB_SUBMIT_MODE=1 :qsub run.sh as a single job in queue, once run, the resouces are
#                   scheduled according to work flow choreography (good for crowded queue)
#                   (could be wasting some resources if not choreographed carefully)
#               =2 :./run.sh run directly, each component submitted into queue separately
#                   no choreography needed, -o is discarded, jobs are schedule by host PBS. 
#                   (good for fast queue)

. $CONFIG_FILE

n=$1  # num of tasks job uses
o=$2  # offset location in task list, useful for several jobs to run together
ppn=$3  # proc per node for the job
exe=$4  # executable

###stampede
if [[ $HOSTTYPE == "stampede" ]]; then

  if [ $JOB_SUBMIT_MODE == 1 ]; then

    export SLURM_NTASKS=$((ppn*$SLURM_NNODES))
    export SLURM_NPROCS=$((ppn*$SLURM_NNODES))
    export SLURM_TACC_CORES=$((ppn*$SLURM_NNODES))
    export SLURM_TASKS_PER_NODE="$ppn(x$SLURM_NNODES)"
    ibrun -n $n -o $o $exe

  fi
fi

###jet
if [[ $HOSTTYPE == "jet" ]]; then

  if [ $JOB_SUBMIT_MODE == 1 ]; then
    rm -f nodefile_avail
    for i in `seq 1 $((PBS_NP/$HOSTPPN))`; do 
      cat $PBS_NODEFILE |head -n$((i*$HOSTPPN)) |tail -n$ppn >> nodefile_avail
    done
    cat nodefile_avail |head -n$((o+$n)) |tail -n$n > nodefile 
    mpiexec.mpirun_rsh -np $n -machinefile nodefile OMP_NUM_THREADS=1 $exe
 
  elif [ $JOB_SUBMIT_MODE == 2 ]; then
    nodes=`echo "($n+$ppn-1)/$ppn" |bc`
    jobname=`basename $exe |awk -F. '{print $1}'`
    cat << EOF > run_$jobname.sh
#!/bin/bash
#PBS -A hfip-psu
#PBS -N $jobname
#PBS -l walltime=2:00:00
#PBS -q batch
#PBS -l partition=ujet:tjet:sjet:vjet
#PBS -l nodes=$nodes:ppn=$ppn
#PBS -j oe
#PBS -d .
source ~/.bashrc
cd `pwd`
mpiexec -np $n $exe >& $jobname.log
EOF
    qsub run_$jobname.sh >& job_submit.log
    #wait for job to finish
    jobid=`cat job_submit.log |awk -F. '{print $1}'`
    jobstat=1
    until [[ $jobstat == 0 ]]; do
      sleep 1m
      jobstat=`/apps/torque/default/bin/qstat |grep $jobid |awk '{if($5=="R" || $5=="Q") print 1; else print 0;}'`
    done
  fi
fi

###define your own mpiexec here if needed:
#if [[ $HOSTTYPE == "yourHPC" ]]; then
#  
#fi
