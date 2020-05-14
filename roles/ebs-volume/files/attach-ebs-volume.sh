#!/usr/bin/env bash
set -e

function HELP {
>&2 cat << EOF

  Usage: ${0} -d device-letter -m mountpoint [-u user]

  This script creates and attaches an encrypted EBS volume.  

    -d dev-letter The device letter. This should be a single character (usually
                  h or later) that is used to identify the device. Note that the
                  device name specified by Amazon and understood by Ubuntu are
                  different.
                  (e.g. Specifying h will appear as /dev/sdh in Amazon and map
                  to /dev/xvdh under Ubuntu, if you're using nitro your path in 
                  Ubuntu will be /dev/nvmeXn1 where X ∈ ℝ hopefully).

    -m mountpoint The fs mountpoint (will be created if necessary).

    -u user       [optional] chown the mountpoint to this user.

    -o options    [optional] Specify file system options (defaults to "defaults")

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

 
OPTIONS="defaults"

# Process options
while getopts d:m:u:s:k:t:i:xo:h FLAG; do
  case $FLAG in
    d)
      DEVICE_LETTER=$OPTARG
      ;;
    m)
      MOUNTPOINT=$OPTARG
      ;;
    u)
      MOUNT_USER=$OPTARG
      ;;
    o)
      OPTIONS=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${DEVICE_LETTER}" ]; then
  echo "Must specify a device letter"
  exit 1
fi

if [ -z "${MOUNTPOINT}" ]; then
  echo "Must specify a mountpoint"
  exit 1
fi

function find_nvme_device {
  local expected_device="sd${DEVICE_LETTER}"
  local nvm_devices=$(ls /dev/nvme?n1)

  for nvm_device in ${nvm_devices}; do
    nvme id-ctrl -v ${nvm_device} | grep -q ${expected_device}
    if [ $? -eq 0 ]; then
      echo "${nvm_device}"
      return 0
    fi
  done

  echo "???"
  return 0
}

function find_uuid {
  local id=basename ${UBUNTU_DEVICE}
  lsblk -o +UUID | grep "^${id}" | awk '{print $8}'
}

function find_device {
  # EBS volumes are exposed as NVMe block devices on Nitro-based instances
  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvme-ebs-volumes.html
  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html#ec2-nitro-instances
  device=$(find_nvme_device)
  while [[ ${counter} -lt 10 && ${device} == "???" ]]; do
    sleep 1
    device=$(find_nvme_device)
    counter=$((counter + 1))

    >&2 echo "${device} ${counter} $?"
  done

  if [[ ${device} == "???" ]]; then
    # Most of our instance types are Nitro-based,
    # but if we can't find an nvme device, try /xvd*
    >&2 echo "Could not find corresponding nvme device for /dev/sd${DEVICE_LETTER}"
    >&2 echo "Trying non-nvme device /dev/xvd${DEVICE_LETTER}"
    echo "/dev/xvd${DEVICE_LETTER}"
    return 1
  fi

  echo ${device}
}

function wait_for_device {
  local DEVICE=$1
  local counter=0
  while [ ${counter} -lt 60 -a ! -b "${DEVICE}" ]; do
    counter=$((counter + 1))
    sleep 1
  done
  if [ ! -b "${DEVICE}" ]; then
    echo "Device ${DEVICE} still not available after 60 seconds"
    return 1
  fi
}
 
UBUNTU_DEVICE=$(find_device)
wait_for_device ${UBUNTU_DEVICE}
UUID=$(find_uuid)

if [ -n "${MOUNTPOINT}" ]; then
  mkdir -p ${MOUNTPOINT}
  mkfs -t ext4 ${UBUNTU_DEVICE}
  echo "UUID=${UUID} ${MOUNTPOINT} ext4 ${OPTIONS} 0 0" >> /etc/fstab
  mount ${MOUNTPOINT}
  if [ -n "${MOUNT_USER}" ]; then
    chown ${MOUNT_USER} ${MOUNTPOINT}
  fi
fi