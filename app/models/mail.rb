require 'recaptcha'

class Mail
  include ReCaptcha::AppHelper

  attr_reader :page, :config, :data, :errors
  def initialize(page, config, data)
    @page, @config, @data = page, config.with_indifferent_access, data[:mailer]
    @params = data
    @rip = data[:rip]  # Remote id
    @required = @data.delete(:required)
    @errors = {}
  end

  def self.valid_config?(config)
    return false if config['recipients'].blank? and config['recipients_field'].blank?
    return false if config['from'].blank? and config['from_field'].blank?
    true
  end

  def valid?
    unless defined?(@valid)
      @valid = true
      if recipients.blank? and !is_required_field?(config[:recipients_field])
        errors['form'] = 'Recipients are required.'
        @valid = false
      end

      if recipients.any?{|e| !valid_email?(e)}
        errors['form'] = 'Recipients are invalid.'
        @valid = false
      end

      if from.blank? and !is_required_field?(config[:from_field])
        errors['form'] = 'From is required.'
        @valid = false
      end

      if !valid_email?(from)
        errors['form'] = 'From is invalid.'
        @valid = false
      end

      if validate_recap(@params, errors) == 'false'
        errors['recap_error'] = "The words you entered are incorrect, please re-enter them."
        @valid = false
      end

      if @required
        @required.each do |name, msg|
          if data[name].blank?
            errors[name] = ((msg.blank? || %w(1 true required).include?(msg)) ? "is required." : msg)
            @valid = false
          end
        end
      end

#      if validate_recap(params, recap_error)
#        errors['recap_error'] = "The words you entered are incorrect, please re-enter them."
#        @valid = false
#      end
    end
    @valid
  end

  def from
    config[:from] || data[config[:from_field]]
  end

  def recipients
    config[:recipients] || data[config[:recipients_field]].split(/,/).collect{|e| e.strip}
  end

  def reply_to
    config[:reply_to] || data[config[:reply_to_field]]
  end

  def sender
    config[:sender]
  end

  def subject
    data[:subject] || config[:subject] || "Form Mail from #{page.request.host}"
  end
  
  def cc
    data[config[:cc_field]] || config[:cc] || ""
  end
  
  def send
    return false if not valid?

    plain_body = (page.part( :email ) ? page.render_part( :email ) : page.render_part( :email_plain ))
    html_body = page.render_part( :email_html ) || nil

    bugs = ""
    if( data["bugs"] )
      bugs = "Category: #{data["bugs"]}"
    end

    if plain_body.blank? and html_body.blank?
      plain_body = <<-EMAIL
#{bugs}
The following information was posted:
#{data.to_hash.to_yaml}
      EMAIL
    end

    headers = { 'Reply-To' => reply_to || from }
    if sender
      headers['Return-Path'] = sender
      headers['Sender'] = sender
    end

    Mailer.deliver_generic_mail(
      :recipients => recipients,
      :from => from,
      :subject => subject,
      :plain_body => plain_body,
      :html_body => html_body,
      :cc => cc,
      :headers => headers
    )
    @sent = true
  rescue Exception => e
    errors['base'] = e.message
    @sent = false
  end

  def sent?
    @sent
  end

  protected

  def valid_email?(email)
    (email.blank? ? true : email =~ /.@.+\../)
  end
  
  def is_required_field?(field_name)
    @required && @required.any? {|name,_| name == field_name}
  end
end
