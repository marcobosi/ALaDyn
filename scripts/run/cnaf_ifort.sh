#!/bin/bash


NUM_OF_MPI_TASKS=16
OMP_THREADS_PER_MPI_TASK=1

EXECUTABLE="./ALaDyn"
stderr_file=epic006.txt
stdout_file=opic006.txt

job=job_test_ifort.cmd
job_name=impi
queue=hpc_inf

###########################
TOT_NUMBER_OF_CORES=$(($NUM_OF_MPI_TASKS * OMP_THREADS_PER_MPI_TASK))
rm -f $job
touch $job
chmod 755 $job

touch ${stderr_file}
touch ${stdout_file}

{
  echo "#BSUB -J ${job_name}"
  echo "#BSUB -o %J.out"
  echo "#BSUB -e %J.err"
  echo "#BSUB -q ${queue}"
  echo "#BSUB -n 32"
#  echo "#BSUB -n ${TOT_NUMBER_OF_CORES}"

#force me to use just this machine with 32 cores
  echo "#BSUB -m \"hpc-200-06-23\""
# hpc-200-06-21\""
  echo "module load compilers/gcc-4.9.0"
  echo "module load compilers/intel-parallel-studio-2017"
  echo "module load boost_1_56_0_gcc4_9_0"
  echo "export TMI_CONFIG=/shared/software/compilers/impi/intel64/etc/tmi.conf"
  echo "export OMP_NUM_THREADS=$OMP_THREADS_PER_MPI_TASK"
  echo "export OMP_PLACES=cores"
  echo "export OMP_PROC_BIND=close"
#  echo "export OMP_PROC_BINC=TRUE"
  echo "/shared/software/compilers/impi/intel64/bin/mpirun -np ${NUM_OF_MPI_TASKS} -genv PSM_SHAREDCONTEXTS_MAX 8 -genv I_MPI_FABRICS shm:tmi ${EXECUTABLE} >> ${stdout_file} 2>> ${stderr_file}"
} > $job

bsub < $job

