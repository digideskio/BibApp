# This controller signs up new users, and activates their accounts
class UsersController < ApplicationController
  
  # Require user be logged in for *everything* except signing up, or activating an account
  before_filter :login_required, :except => [ :show, :new, :create, :activate ]

  make_resourceful do 
    build :index, :show, :new, :edit
    
    before :index do
      # find first letter of usernames (in uppercase, for paging mechanism)
      @a_to_z = User.letters
        
      #get current page  
      @page = params[:page] || @a_to_z[0]
      
      #get all objects for that current page
      @current_objects = User.where("upper(email) like ?", "#{@page}%").order("upper(email)")
    end
  end

 
  # Create - signs up a new user
  def create
    cookies.delete :auth_token
    # protects against session fixation attacks, wreaks havoc with 
    # request forgery protection.
    # uncomment at your own risk
    # reset_session
    @user = User.new(params[:user])
    @user.save
    if @user.errors.empty?
      flash[:notice] = t('common.users.flash_create', :email => @user.email)
      redirect_back_or_default($APPLICATION_URL)
    else
      render :action => 'new'
    end
  end
  
  
  # Update - update user email
  def update
    @user = User.find(params[:id])
    new_email = params[:user][:email]
    code = @user.email_update_code(new_email)

    if new_email == @user.email
      flash[:notice] = t('common.users.flash_update_no_change')
      redirect_to(edit_user_url(@user)) and return
    end

    #We set the email but don't save so that we can use validations
    old_email = @user.email
    @user.email = new_email
    if !@user.valid?
      @user.email = old_email
      render :action => 'edit'
    else
      url = update_email_user_url(@user, :new_email => new_email, :code => code)
      UserMailer.update_email(@user, url).deliver
      flash[:notice] = t('common.users.flash_update_success', :email => new_email)
      redirect_back_or_default(root_url)
    end

  end

  def update_email
    user = User.find(params[:id])
    #retrieve code and new email from url
    code = params[:code]
    new_email = params[:new_email]
    if code == user.email_update_code(new_email)
      user.email = new_email
      if user.save
        flash[:notice] = t('common.users.flash_update_email_success')
        redirect_back_or_default(root_url)
      else
        flash[:notice] = t('common.users.flash_update_email_duplicate')
        redirect_to(edit_user_url(user))
      end
    else
      flash[:notice] = t('common.users.flash_update_email_invalid')
      redirect_to(edit_user_url(user))
    end
  end

  # Activates a new user account (after user clicks on link in activation email)
  def activate
    user = params[:activation_code].blank? ? false : User.find_by_activation_code(params[:activation_code])
    if user and !user.active?
      user.activate
      flash[:notice] = t('common.users.flash_activate')
    end
    redirect_back_or_default(root_url)
  end

end
