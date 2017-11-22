#
# Cookbook Name:: ephemeral_raid
# Library:: helper
#
# Copyright (C) 2013 Medidata Worldwide
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Notes:
#
# This helper started life as work by RightScale, also under Apache 2.0 License
# https://github.com/rightscale-cookbooks/ephemeral_lvm/tree/white_13_05_acu114901_implement_ephemeral_library_cookbook
#

module EphemeralDevices
  module Helper
    # Identifies the ephemeral devices available on a cloud server and returns them as an array. This method also does
    # the mapping required for Xen hypervisors (/dev/sdX -> /dev/xvdX).
    #
    # @param cloud [String] the name of cloud
    # @param node [Chef::Node] the Chef node
    #
    # @return [Array<String>] list of available ephemeral devices.
    #
    def self.get_ephemeral_devices(cloud, node)
      if cloud == 'gce'
        # According to the GCE documentation, the instances have links for ephemeral disks as
        # /dev/disk/by-id/google-ephemeral-disk-* and for local SSDs as /dev/disk/by-id/google-local-ssd-*.
        # Refer to https://developers.google.com/compute/docs/disks for more information.
        #
        if node[cloud]['instance'] && node[cloud]['instance']['disks']
          disks = node[cloud]['instance']['disks']
        elsif node[cloud]['attached_disks'] && node[cloud]['attached_disks']['disks']
          disks = node[cloud]['attached_disks']['disks']
        else
          disks = []
        end
        ephemeral_devices = disks.map do |device|
          if device['type'] == "EPHEMERAL" && device['deviceName'].match(/^ephemeral-disk-\d+$/)
            "/dev/disk/by-id/google-#{device['deviceName']}"
          elsif device['type'] == "LOCAL-SSD" && device['deviceName'].match(/^local-ssd-\d+$/)
            # As of 8/22/17, there is a GCE bug where the symlinks under /dev/disk/by-id/ are not created
            # correctly for NVMe local SSD's. Work around by returning the actual NVMe block devices (/dev/nvme0n*).
            # See https://googlecloudplatform.uservoice.com/forums/302595-compute-engine/suggestions/17739364--dev-disk-by-id-contains-only-one-nvme-device-sym.
            scsiDevice = "/dev/disk/by-id/google-#{device['deviceName']}"
            nvmeDeviceNumber = device['deviceName'].gsub(/^local-ssd-/, '').to_i + 1
            nvmeDevice = "/dev/nvme0n#{nvmeDeviceNumber}"
            File.exist?(nvmeDevice) ? nvmeDevice : scsiDevice
          end
        end
      else
        # If the cloud plugin supports ephemeral block device mappings, use them to obtain the device IDs.
        ephemeral_devices = node[cloud].select { |key, value| key.match(/^block_device_mapping_ephemeral\d+$/) }.map { |key, value|
          value.start_with?('/dev/') ? value : "/dev/#{value}"
        }

        # Servers running on Xen hypervisor require the block device to be in /dev/xvdX instead of /dev/sdX
        if node.attribute?('virtualization') && node['virtualization']['system'] == "xen"
          ephemeral_devices = EphemeralDevices::Helper.fix_device_mapping(
              ephemeral_devices,
              node['block_device'].keys
          )
        end

        # NVMe SSD devices aren't captured by ohai, so add them manually.
        ephemeral_devices.concat Dir.glob('/dev/nvme*n*')
      end

      puts "Ephemeral devices found for cloud '#{cloud}': #{ephemeral_devices.inspect}"
      Chef::Log.info "Ephemeral devices found for cloud '#{cloud}': #{ephemeral_devices.inspect}"

      ephemeral_devices
    end

    # Fixes the device mapping on Xen hypervisors. When using Xen hypervisors, the devices are mapped from /dev/sdX to
    # /dev/xvdX. This method will identify if mapping is required (by checking the existence of unmapped device) and
    # map the devices accordingly.
    #
    # @param devices [Array<String>] list of devices to fix the mapping
    # @param node_block_devices [Array<String>] list of block devices currently attached to the server
    #
    # @return [Array<String>] list of devices with fixed mapping
    #
    def self.fix_device_mapping(devices, node_block_devices)
      devices.map! do |device|
        if node_block_devices.include?(device.match(/\/dev\/([a-z]+)$/)[1])
          device
        else
          fixed_device = device.sub("/sd", "/xvd")
          if node_block_devices.include?(fixed_device.match(/\/dev\/([a-z]+)$/)[1])
            fixed_device
          else
            Chef::Log.warn "could not find ephemeral device: #{device}"
            nil
          end
        end
      end
      devices.compact
    end
  end
end
