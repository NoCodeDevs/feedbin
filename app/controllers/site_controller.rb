class SiteController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token, only: [:service_worker]

  def index
    @entries = Entry.includes(:feed)
                    .order(published: :desc)
                    .limit(60)
    render "site/public_feed", layout: false
  end

  def subscribe
    redirect_to root_url(request.query_parameters)
  end

  def service_worker
  end

  def manifest
    @color = Colors.fetch(params[:theme])
    @icons = [
      {
        src: helpers.asset_url("icon-manifest.png"),
        sizes: "192x192",
        type: "image/png",
        purpose: "maskable"
      },
      {
        src: helpers.asset_url("icon-manifest-large.png"),
        sizes: "512x512",
        type: "image/png",
        purpose: "any"
      }
    ]

    render formats: :json, content_type: "application/manifest+json"
  end

  def auto_sign_in
    sign_in User.first
    redirect_to root_url
  end

  private

  def check_user
    if current_user.suspended && !native?
      redirect_to settings_billing_url, alert: "Please update your billing information to use Feedbin."
    elsif current_user.plan.restricted? && !native?
      redirect_to settings_url, alert: "Your subscription does not currently include web access."
    end
  end
end
