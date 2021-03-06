require 'test_helper'

class Kaui::AccountsControllerTest < Kaui::FunctionalTestHelper

  test 'should get index' do
    get :index
    assert_response 200
  end

  test 'should get index one account' do
    parameters = {
      :fast => '1',
      :q => @account.account_id
    }

    get :index, parameters
    assert_response :redirect
    assert_redirected_to account_path(@account.account_id)

    parameters = {
        :fast => '1',
        :q => 'THIS_IS_NOT_FOUND_REDIRECT'
    }

    get :index, parameters
    assert_response :redirect
    assert_redirected_to home_path
  end

  test 'should list accounts' do
    # Test pagination
    get :pagination, :format => :json
    verify_pagination_results!
  end

  test 'should search accounts' do
    # Test search
    get :pagination, :sSearch => 'foo', :format => :json
    verify_pagination_results!
  end

  test 'should handle Kill Bill errors when showing account details' do
    account_id = SecureRandom.uuid.to_s
    get :show, :account_id => account_id
    assert_redirected_to home_path
    assert_equal "Error while communicating with the Kill Bill server: Error 404: Object id=#{account_id} type=ACCOUNT doesn't exist!", flash[:error]
  end

  test 'should find account by id' do
    get :show, :account_id => @account.account_id
    assert_response 200
    assert_not_nil assigns(:tags)
    assert_not_nil assigns(:account_emails)
    assert_not_nil assigns(:overdue_state)
    assert_not_nil assigns(:payment_methods)
  end

  test 'should handle Kill Bill errors when creating account' do
    post :create
    assert_redirected_to home_path
    assert_equal 'Required parameter missing: account', flash[:error]

    external_key = SecureRandom.uuid.to_s
    post :create, :account => {:external_key => external_key}
    assert_redirected_to account_path(assigns(:account).account_id)

    post :create, :account => {:external_key => external_key}
    assert_template :new
    assert_equal "Error while creating account: Error 409: Account already exists for key #{external_key}", flash[:error]
  end

  test 'should create account' do
    get :new
    assert_response 200
    assert_not_nil assigns(:account)

    post :create,
         :account => {
             :name => SecureRandom.uuid.to_s,
             :external_key => SecureRandom.uuid.to_s,
             :email => SecureRandom.uuid.to_s + '@example.com',
             :time_zone => '-06:00',
             :country => 'AR',
             :is_migrated => '1'
         }
    assert_redirected_to account_path(assigns(:account).account_id)
    assert_equal 'Account was successfully created', flash[:notice]

    assert_equal '-06:00', assigns(:account).time_zone
    assert_equal 'AR', assigns(:account).country
    assert assigns(:account).is_migrated
    assert !assigns(:account).is_notified_for_invoices
  end

  test 'should update account' do
    get :edit, :account_id => @account.account_id
    assert_response 200
    assert_not_nil assigns(:account)

    latest_account_attributes = assigns(:account).to_hash
    put :update,
        :account_id => @account.account_id,
        :account => latest_account_attributes.merge({
            :name => SecureRandom.uuid.to_s,
            :email => SecureRandom.uuid.to_s + '@example.com'
        })
    assert_redirected_to account_path(assigns(:account).account_id)
    assert_equal 'Account successfully updated', flash[:notice]
  end

  test 'should be redirected if no payment_method_id is specified when setting default payment method' do
    put :set_default_payment_method, :account_id => @account.account_id
    assert_redirected_to account_path(@account.account_id)
    assert_equal 'Required parameter missing: payment_method_id', flash[:error]
  end

  test 'should handle Kill Bill errors when setting default payment method' do
    account_id = SecureRandom.uuid.to_s
    put :set_default_payment_method, :account_id => account_id, :payment_method_id => @payment_method.payment_method_id
    assert_redirected_to home_path
    assert_equal "Error while communicating with the Kill Bill server: Error 404: Object id=#{account_id} type=ACCOUNT doesn't exist!", flash[:error]
  end

  test 'should set default payment method' do
    put :set_default_payment_method, :account_id => @account.account_id, :payment_method_id => @payment_method.payment_method_id
    assert_response 302
  end

  test 'should handle Kill Bill errors when paying all invoices' do
    account_id = SecureRandom.uuid.to_s
    post :pay_all_invoices, :account_id => account_id
    assert_redirected_to home_path
    assert_equal "Error while communicating with the Kill Bill server: Error 404: Object id=#{account_id} type=ACCOUNT doesn't exist!", flash[:error]
  end

  test 'should pay all invoices' do
    post :pay_all_invoices, :account_id => @account.account_id, :is_external_payment => true
    assert_response 302
  end

  test 'should trigger invoice' do
    parameters = {
      :account_id => @account2.account_id,
      :dry_run => '0'
    }

    post :trigger_invoice, parameters
    assert_equal 'Nothing to generate for target date today', flash[:notice]
    assert_redirected_to account_path(@account2.account_id)

    today_next_month = (Date.parse(@kb_clock['localDate']) >> 1).to_s
    # generate a dry run invoice
    parameters = {
      :account_id => @account.account_id,
      :dry_run => '1',
      :target_date => today_next_month
    }

    post :trigger_invoice, parameters
    assert_response :success

    # persist it
    parameters[:dry_run] = '0'
    post :trigger_invoice, parameters
    assert_response :redirect
    assert_match /Generated invoice.*for target date.*/, flash[:notice]
    a_tag = /<a.href="(?<href>.*?)">/.match(@response.body)
    assert_redirected_to a_tag[:href]
  end

  test 'should get next_invoice_date' do
    get :next_invoice_date, :account_id => @account.account_id
    assert_not_nil @response.body
  end

  test 'should validate external key if found' do
    get :validate_external_key, :external_key => 'foo'
    assert_response :success
    assert_equal JSON[@response.body]['is_found'], false

    external_key = SecureRandom.uuid.to_s
    post :create, :account => {:external_key => external_key}
    assert_redirected_to account_path(get_redirected_account_id)

    get :validate_external_key, :external_key => external_key
    assert_response :success
    assert_equal JSON[@response.body]['is_found'], true
  end

  test 'should link and un-link to parent' do
    parent = create_account(@tenant)
    child = create_account(@tenant)

    # force an error linking a parent account
    child.parent_account_id = SecureRandom.uuid.to_s
    put :link_to_parent, {
        :account => child.to_hash,
        :account_id => child.account_id
    }
    assert_equal "Parent account id not found: #{child.parent_account_id}",flash[:error]
    assert_redirected_to account_path(child.account_id)

    # link parent account
    child.parent_account_id = parent.account_id
    put :link_to_parent, {
        :account => child.to_hash,
        :account_id => child.account_id
    }
    assert_equal 'Account successfully updated',flash[:notice]
    assert_redirected_to account_path(child.account_id)

    # un-link parent account
    delete :link_to_parent, :account_id => child.account_id
    assert_equal 'Account successfully updated',flash[:notice]
    assert_redirected_to account_path(child.account_id)

  end

  test 'should set email notifications configuration if plugin is available' do

    parameters = {
        :configuration => {
          :account_id => @account.account_id,
          :event_types => ['INVOICE_NOTIFICATION']
        }
    }

    post :set_email_notifications_configuration, parameters
    assert_equal('Email notification plugin is not installed',flash[:error]) unless flash[:error].blank?
    assert_equal("Email notifications for account #{@account.account_id} was successfully updated",flash[:notice]) if flash[:error].blank?
    assert_redirected_to account_path(@account.account_id)

  end

  private

    def get_redirected_account_id

      fields = /<a.href="http:\/.*\/.*?\/(?<id>.*?)">/.match(@response.body) if fields.nil?

      return nil if fields.nil?

      fields.nil? ? nil : fields[:id]
    end

end
