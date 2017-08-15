#!/bin/bash

#
# Burkhardt Rockel / Helmholtz-Zentrum Geesthacht
# Initial Version: 2009/09/02
# Latest Version:  2016/12/16 (Version 2.3)
#

if [[ ${0%/*} == "."  || ${0%/*} == $PWD ]]
then :
else
  echo  === ERROR === subchain must be called from within its directory
  echo "               " it was called from: ${0%/*}
  exit 1
fi

source job_settings.sh

CURRENT_DATE=$(echo ${YDATE_START} | cut -c1-6)
STOP_DATE=$(echo ${YDATE_STOP} | cut -c1-6)
overwrite=false
n=true #normal printing mode
v=false #verbose printing mode

while [[ $# -gt 0 ]]
do
  key="$1"
  case $key in
      -g|--gcm)
      GCM=$2
      shift
      ;;
      -x|--exp)
      EXP=$2
      shift
      ;;
      -i|--input)
      EXPPATH=$2
      shift
      ;;
       -s|--start)
      CURRENT_DATE=$2
      shift
      ;;
      -e|--end)
      STOP_DATE=$2
      shift
      ;;
      -S|--silent)
      n=false
      ;;
      -V|--verbose)
      v=true
      ;;
      -O|--overwrite)
      overwrite=true
      ;;
      *)
      echo unknown option!
      ;;
  esac
  shift
done

EXPPATH=${GCM}/${EXP}
EXPID=${GCM}_${EXP}

echo "GCM:" ${GCM}
echo "Experiment:" ${GCM}
echo "Path to input data:" ${INPATH}
echo "Start date:" ${CURRENT_DATE}
echo "Stop date:" ${STOP_DATE}

#printing modes

function echov {
  if ${v}
  then
    echo $1
  fi
}

function echon {
  if ${n}
  then
   echo $1
  fi
}

if [ ! -d ${INPATH} ]
then
  echo "Input path does not exist! Exiting..."
  exit
fi


if [ ! -d ${WORKDIR}/${EXPPATH} ]
then
  mkdir -p ${WORKDIR}/${EXPPATH}
fi



INPDIR=${INPUTPOST}/${EXPPATH}
OUTDIR=${OUTPUTPOST}/${EXPPATH}
if [ ! -d ${INPUTPOST}/${EXPPATH} ]
then
  mkdir -p ${INPUTPOST}/${EXPPATH}
fi

YYYY=$(echo ${CURRENT_DATE} | cut -c1-4)
MM=$(echo ${CURRENT_DATE} | cut -c5-6)
MMint=${MM}
if [ $(echo ${MM} | cut -c1) -eq 0 ]
then
  MMint=$(echo ${MMint} | cut -c2  )
fi



#################################################
# Post-processing loop
#################################################

#build constant variables (as FR_LAND and H_SURF)
#TODO: maybe unzip first with gunzip if applicable


#... set number of boundary lines to be cut off in the time series data
NBOUNDCUT=${NBOUNDCUT}
let "IESPONGE = ${IE_TOT} - NBOUNDCUT - 1"
let "JESPONGE = ${JE_TOT} - NBOUNDCUT - 1"

constDone=false #boolean to save if constant variables have already been processed

while [ ${CURRENT_DATE} -le ${STOP_DATE} ]
do
  YYYY_MM=${YYYY}_${MM}
  CURRDIR=${YYYY}/output
  echon "################################"
  echon "# Processing time ${YYYY_MM}"
  echon "################################"

  if [ ! -d ${INPDIR}/${YYYY} ]
  then
    if [ -f ${INPATH}/*${YYYY}.tar ]
    then
      echon "Extracting archive of year ${YYYY}..."
      tar -xf ${INPATH}/*${YYYY}.tar -C ${INPDIR}
      echon "Done"
   	else
   	  echon "Neither directory nor tar file for year ${YYYY} exists in input directory! Exiting..."
   	  exit
   	fi
  fi

  if [ ! -d ${OUTDIR}/${YYYY_MM} ]
  then
    mkdir -p ${OUTDIR}/${YYYY_MM}
  fi

	DATE_START=$(date +%s)
	DATE1=${DATE_START}

	##################################################################################################
	# build time series
	##################################################################################################

	export IGNORE_ATT_COORDINATES=1  # setting for better rotated coordinate handling in CDO

	#... uncompress files if they have been compressed by gzip in the "arch" job
	if [  ${ITYPE_COMPRESS_ARCH} -eq 2 ]
	then
	  echon "**** gzip uncompression"
	  gunzip -r ${INPDIR}/${CURRDIR}/*
	fi


  #... cut of the boundary lines from the constant data file and copy it
  if [ ! -f ${WORKDIR}/${EXPPATH}/cclm_const.nc ]
  then
    echon "Copy constant file"
    ncks -h -d rlon,${NBOUNDCUT},${IESPONGE} -d rlat,${NBOUNDCUT},${JESPONGE} ${INPDIR}/${YYYY}/output/out01/lffd${SIM_START}c.nc ${WORKDIR}/${EXPPATH}/cclm_const.nc
  fi






  #function to process constant variables
  function constVar {
	if [ ! -f ${OUTDIR}/$1.nc ] ||  ${overwrite}
	then
		echon "Building file for constant variable $1"
  	${NCO_BINDIR}/ncks -h -A -v $1,rotated_pole ${WORKDIR}/${EXPPATH}/cclm_const.nc ${OUTDIR}/$1.nc
	else
  	echov "File for constant variable $1 already exists. Skipping..."
	fi
	}

	#... functions for building time series
	function timeseries {  # building a time series for a given quantity
	cd ${INPDIR}/${CURRDIR}/$2
	if [ ! -f ${OUTDIR}/${YYYY_MM}/$1_ts.nc ] ||  ${overwrite}
	then
		echon "Building time series for variable $1"
	  ${NCO_BINDIR}/ncrcat -h -O -d rlon,${NBOUNDCUT},${IESPONGE} -d rlat,${NBOUNDCUT},${JESPONGE} -v $1 lffd${CURRENT_DATE}*[!cpz].nc ${OUTDIR}/${YYYY_MM}/$1_ts.nc
	  ${NCO_BINDIR}/ncks -h -A -d rlon,${NBOUNDCUT},${IESPONGE} -d rlat,${NBOUNDCUT},${JESPONGE} -v lon,lat,rotated_pole ${INPDIR}/${CURRDIR}/$2/lffd${CURRENT_DATE}0100.nc ${OUTDIR}/${YYYY_MM}/$1_ts.nc
  else
  	echov "Time series for variable $1 already exists. Skipping..."
  fi
	}

	PLEVS=(4 200. 500. 850. 925.) # list of pressure levels. Must be the same as or a subset
		                           # of the list in the specific GRIBOUT
	function timeseriesp {  # building a time series for a given quantity on pressure levels
	NPLEV=1
	while [ ${NPLEV} -le ${PLEVS[0]} ]
	do
	  PASCAL=$(python -c "print(${PLEVS[$NPLEV]} * 100.)")
	  PLEV=$(python -c "print(int(${PLEVS[$NPLEV]}))")
	  cd ${INPDIR}/${CURRDIR}/$2

  	if [ ! -f ${OUTDIR}/${YYYY_MM}/${1}${PLEV}p_ts.nc ] ||  ${overwrite}
    then
  		echon "Building time series at pressure level ${PLEV} hPa for variable $1"
	    ${NCO_BINDIR}/ncrcat -h -O -d rlon,${NBOUNDCUT},${IESPONGE} -d rlat,${NBOUNDCUT},${JESPONGE} -d pressure,${PASCAL},${PASCAL} -v $1 lffd${CURRENT_DATE}*p.nc ${OUTDIR}/${YYYY_MM}/${1}${PLEV}p_ts.nc
  	  ${NCO_BINDIR}/ncks -h -A -d rlon,${NBOUNDCUT},${IESPONGE} -d rlat,${NBOUNDCUT},${JESPONGE} -v lon,lat,rotated_pole ${INPDIR}/${CURRDIR}/$2/lffd${CURRENT_DATE}0100p.nc ${OUTDIR}/${YYYY_MM}/${1}${PLEV}p_ts.nc
	  else
    	echov "Time series for variable $1 at pressure level ${PLEV}  already exists. Skipping..."
	  fi
	  let "NPLEV = NPLEV + 1"

	done
	}

	ZLEVS=(4 100. 1000. 2000. 5000.) # list of height levels. Must be the same as or a subset
		                           # of the list in the specific GRIBOUT
	function timeseriesz {
	NZLEV=1
	while [ ${NZLEV} -le ${ZLEVS[0]} ]
	do
	  ZLEV=$(python -c "print(int(${ZLEVS[$NZLEV]}))")
	  cd ${INPDIR}/${CURRDIR}/$2

  	if [ ! -f ${OUTDIR}/${YYYY_MM}/${1}${ZLEV}z_ts.nc ] ||  ${overwrite}
    then
  		echon "Building time series at height level ${ZLEV} m for variable $1"
	    ${NCO_BINDIR}/ncrcat -h -O -d rlon,${NBOUNDCUT},${IESPONGE} -d rlat,${NBOUNDCUT},${JESPONGE} -d altitude,${ZLEV}.,${ZLEV}. -v $1 lffd${CURRENT_DATE}*z.nc ${OUTDIR}/${YYYY_MM}/${1}${ZLEV}z_ts.nc
	    ${NCO_BINDIR}/ncks -h -A -d rlon,${NBOUNDCUT},${IESPONGE} -d rlat,${NBOUNDCUT},${JESPONGE} -v lon,lat,rotated_pole ${INPDIR}/${CURRDIR}/$2/lffd${CURRENT_DATE}0100z.nc ${OUTDIR}/${YYYY_MM}/${1}${ZLEV}z_ts.nc
	  else
    	echov "Time series for variable $1 at height level ${ZLEV} m  already exists. Skipping..."
	  fi
	  let "NZLEV = NZLEV + 1"
	done
	}


	DATE_START=$(date +%s)

  #process constant variables
  if ! ${constDone}
  then
    constVar FR_LAND
    constVar HSURF
    constDone=true
  fi

	# --- build time series for selected variables
	cd ${PFDIR}
	source jobf.sh


	#################################################
	# compress data
	#################################################
	case ${ITYPE_COMPRESS_POST} in

	0)        #... no compression


	  ;;

	1)        #... internal netCDF compression

	  echon "**** internal netCDF compression"
	  cd ${OUTDIR}/${YYYY_MM}

	  FILELIST=$(ls -1)
	  for FILE in ${FILELIST}
	  do
	    ${NC_BINDIR}/nccopy -d 1 -s ${FILE} tmp.nc
	    mv tmp.nc ${FILE}
	  done
	  ;;

	2)       #... gzip compression

	  echon "**** gzip compression"
	  cd ${OUTDIR}/${YYYY_MM}

	  FILELIST=$(ls -1)
	  for FILE in ${FILELIST}
	  do
	    gzip ${FILE}
	  done
	  ;;

	*)

	  echon "**** invalid value for  ITYPE_COMPRESS_ARCH: "${ITYPE_COMPRESS_POST}
	  echon "**** no compression applied"
	  ;;

	esac


	DATE2=$(date +%s)
	#SEC_TS=$(python -c "print ${DATE2}-${DATE1}")
	#echo time used for bulding time series: ${SEC_TS} s


	SEC_TOTAL=$(python -c "print(${DATE2}-${DATE_START})")
	echon "total time for postprocessing: ${SEC_TOTAL} s"

	#echo "END  " ${YYYY} ${MM}  >> ${WORKDIR}/${EXPPATH}/joblogs/post/finish_joblist



  MMint=$(python -c "print(int("${MMint}")+1)")
  if [ ${MMint} -ge 13 ]
  then
    MMint=1
    YYYY=$(python -c "print(int("${YYYY}")+1)")
  fi

  if [ ${MMint} -le 9 ]
  then
    MM=0${MMint}
  else
    MM=${MMint}
  fi

  CURRENT_DATE=${YYYY}${MM}

done
