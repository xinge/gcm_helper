gcm-sender
==========

A ruby port of Google's GCM Sender

## Usage

Create a message:

    m=GcmHelper::Message.new
    m.delay_while_idle=true
    m.add_data('alert', 'push data here it is....')
    m.add_data('timestamp', "#{Time.now}")
    p m.to_s

Create a Sender to send messages to the GCM service using an API Key:

    s=GcmHelper::Sender.new(key)

Sends a message without retrying in case of service unavailability:

    r = s.send_no_retry(m, reg_id_1)

Sends a message to one device, retrying in case of unavailability:

    r = s.send_with_retry(m, reg_id_1, retries=3)

Sends a message without retrying in case of service unavailability:

    r = s.multicast_no_retry(m, [reg_id_1, reg_id_2])

Sends a message to many devices, retrying in case of unavailability:

    r = s.multicast_with_retry(m, [reg_id_1, reg_id_2], retries=3)

