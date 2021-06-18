require 'twitch/chat'
require 'twitch-api'
require 'coinrpc'
require 'bigdecimal'
require 'dotenv/load'
require 'pp'


CONFIRM = ENV["CONF_CONFIRM"].to_i
FEE = ENV["CONF_FEE"].to_f
MINIMUM = "%.8f" % ENV["CONF_MINIMUM"]
WITHDRAWMINIMUM = ENV["CONF_WITHDRAWMINIMUM"].to_f
ADMIN = "211837672"
BOTID = ENV["TWITCH_BOT_ID"]

twitchClient = Twitch::Client.new(
  client_id: ENV["TWITCH_CLIENT_ID"],
  client_secret: ENV["TWITCH_CLIENT_SECRET"]
)

tipClient = CoinRPC::Client.new(ENV["RPC_URL"])


client = Twitch::Chat::Client.new(
  channel: ENV["TWITCH_CHANNEL"], 
  nickname: ENV["TWITCH_NICKNAME"], 
  password: ENV["TWITCH_PASSWORD"]
) do
  # on :join do |channel|
  #   send_message "Hi #{channel}"
  # end

  # on :subscribe do |user|
  #   send_message "Hi #{user.name}, thank you for subscription"
  # end

  # show user balance
  on :message do |message|
    if message.text.include?("!!balance")
      account = message.user.id.to_s

      balance = tipClient.getbalance(account, CONFIRM)

      send_message "@#{message.user.display_name} Your balance is #{balance} TIP"
    end
  end

  # grab user deposit address
  on :message do |message|
    if message.text.include?("!!deposit")
      account = message.user.id.to_s

      address = tipClient.getaccountaddress(account)

      send_message "@#{message.user.display_name} Deposit Tipcoin to this address #{address}"
    end
  end

  # tip specified user
  on :message do |message|
    params = message.text.split(' ')

    if params[0] == "!!tip"
      account = message.user.id.to_s

      if params.count != 3
        send_message "@#{message.user.display_name} Too few arguments for command !!tip"
        next
      end

      

      amount = Float(params[2], exception: false)

      pp amount
      pp amount.to_f.is_a?(Float)
      
      if amount.to_f.is_a?(Float) == false || amount.nil?
        send_message "@#{message.user.display_name} Thats an invalid amount #{amount}"
        next
      end

      amount = BigDecimal(amount.to_s)
      amount = "%.8f" % amount

      to_username = params[1]
      to_user = twitchClient.get_users({login: to_username.gsub("@", "")}).data.first

      # check if twitch returned a user
      if to_user.nil?
        send_message "@#{message.user.display_name} Make sure you mention a real user, cant find #{to_username}"
        next
      end

      to_user_id = to_user.id

      # check if tip is going to self
      if account == to_user_id
        send_message "@#{message.user.display_name} You cannot tip to yourself"
        next
      end

      # check if it's at least minimum
      if amount.to_f < MINIMUM.to_f
        send_message "@#{message.user.display_name} Amount must be at least #{MINIMUM} TIP"
        next
      end

      balance = tipClient.getbalance(account, CONFIRM)

      # check if user account has available balance
      if amount.to_f > balance
        send_message "@#{message.user.display_name} You don't have enough balance"
        next
      end

      # attempt move of funds

      # check if tip is going to bot
      to_bot = (to_user_id == BOTID)
      # assign the destination to the bot admin
      to_user_id = ADMIN if to_bot

      begin
        move_istrue = tipClient.move(account, to_user_id, amount)
      rescue => exception
        pp exception

        send_message "@#{message.user.display_name} im having issues sending that TIP"
        next
      else
        if move_istrue
          send_message "@#{message.user.display_name} just tipped #{to_username} #{amount} TIP"
        end
      end

    end
  end

  # withdraw Tipcoin from user wallet
  on :message do |message|
    params = message.text.split(' ')

    if params[0] == "!!withdraw"
      account = message.user.id.to_s

      pp params
      pp params.count

      if params.count != 3
        send_message "@#{message.user.display_name} Too few arguments for command !!withdraw"
        next
      end

      to_address = params[1]

      pp to_address

      address_validate = tipClient.validateaddress(to_address)

      # invalid address
      if address_validate['isvalid'] == false
        send_message "@#{message.user.display_name} Thats an invalid address"
        next
      end

      amount = Float(params[2], exception: false)

      pp amount
      pp amount.to_f.is_a?(Float)

      if amount.to_f.is_a?(Float) == false || amount.nil?
        send_message "@#{message.user.display_name} Thats an invalid amount #{amount}"
        next
      end

      amount = amount - FEE
      amount = BigDecimal(amount.to_s)
      amount = "%.8f" % amount

      pp amount

      # check if amount meets minimum
      if amount.to_f < WITHDRAWMINIMUM
        send_message "@#{message.user.display_name} Withdraw amount must be at least #{WITHDRAWMINIMUM + FEE} TIP"
        next
      end

      balance = tipClient.getbalance(account, CONFIRM)

      if amount.to_f > balance
        send_message "@#{message.user.display_name} You don't have enough balance to withdraw #{amount} TIP, current balance #{balance} TIP"
        next
      end

      begin
        txid = tipClient.sendfrom(account, to_address, amount)
      rescue => exception
        pp exception

        send_message "@#{message.user.display_name} im having issues creating the transaction"
        next
      else
        if txid.length == 64
          tx = tipClient.gettransaction(txid)

          tipClient.move(account, ADMIN, FEE)

          send_message "@#{message.user.display_name} Withdrawal Complete: transaction id #{txid}"
        end
      end

    end
  end

  # withdraw all Tipcoin from user wallet
  on :message do |message|
    params = message.text.split(' ')

    if params[0] == "!!withdrawall"
      account = message.user.id.to_s

      pp params
      pp params.count

      if params.count != 2
        send_message "@#{message.user.display_name} Too few arguments for command !!withdrawall"
        next
      end

      to_address = params[1]

      pp to_address

      address_validate = tipClient.validateaddress(to_address)

      # invalid address
      if address_validate['isvalid'] == false
        send_message "@#{message.user.display_name} Thats an invalid address"
        next
      end

      balance = tipClient.getbalance(account, CONFIRM)

      balance = Float(balance, exception: false)
      amount = balance - FEE
      amount = BigDecimal(amount.to_s)
      amount = "%.8f" % amount

      pp amount

      # check if amount meets minimum
      if amount.to_f < WITHDRAWMINIMUM
        send_message "@#{message.user.display_name} Withdraw balance must be at least #{WITHDRAWMINIMUM + FEE} TIP"
        next
      end

      begin
        txid = tipClient.sendfrom(account, to_address, amount)
      rescue => exception
        pp exception

        send_message "@#{message.user.display_name} im having issues creating the transaction"
        next
      else
        if txid.length == 64
          tx = tipClient.gettransaction(txid)

          tipClient.move(account, ADMIN, FEE)

          send_message "@#{message.user.display_name} Withdrawal Complete: transaction id #{txid}"
        end
      end

    end
  end

end

client.run!