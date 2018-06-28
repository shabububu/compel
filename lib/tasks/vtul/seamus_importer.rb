class SeamusImporter

  class UserProfile
    attr_accessor :login, :short_bio, :member_role, :member_website_link, 
                  :member_profile_img_src, :member_twitter_link, 
                  :member_facebook_link, :member_google_link,
                  :member_soundcloud_link
  end  

  def import_wp_author(wp_author)
    printf "--- Importing: %s (%s, %s, %s)\n", wp_author.id, wp_author.login, wp_author.email, wp_author.display_name

    user = User.find_by({email: wp_author.email.downcase})
    if user.nil?
      begin
        puts "... User does not yet exist. Proceeding with creation..."

        profile = scrape_user_profile(wp_author.login)
        create_user(wp_author, profile)

        puts "... Waiting ..." # Wait before moving on to not hammer a site?
        sleep(5.seconds)
      rescue URI::InvalidURIError => iurie
        puts "!!!!! User creation failed " + iurie.message
      end
    else
      puts "... User exists. Skipping creation..."
    end
  end

  def scrape_user_profile(login)
    profile_url = "https://www.seamusonline.org/seamus-member/#{login.tr(" ", "-")}"
    puts "... Scraping SEAMUS profile page: "+profile_url

    seamus_profile = HTTParty.get(profile_url)
    profile_page ||= Nokogiri::HTML(seamus_profile)

    profile = UserProfile.new
    profile.short_bio = profile_page.css('.short-bio').children.map { |bio| bio.text }.compact.join(',')
    profile.member_role = profile_page.css('.member-role').children.map { |role| role.text }.compact.join(',')
    profile.member_website_link = get_first_class_href(profile_page, '.member-website-link')
    profile.member_profile_img_src = get_first_class_src(profile_page, '.member-profile-wrap')
    profile.member_twitter_link = get_first_class_href(profile_page, '.member-twitter-link')
    profile.member_facebook_link = get_first_class_href(profile_page, '.member-facebook-link')
    profile.member_google_link = get_first_class_href(profile_page, '.member-google-link')
    profile.member_soundcloud_link = get_first_class_href(profile_page, '.member-soundcloud-link') 
    return profile
  end

  def get_first_class_src(page, class_name)
    page.css(class_name).css('img').first['src'] unless page.css(class_name).css('img').first.nil?
  end

  def get_first_class_href(page, class_name) 
    page.css(class_name).css('a').first['href'] unless page.css(class_name).css('a').first.nil?
  end

  def personal_statement(profile)
    if profile.member_role.empty?
      profile.short_bio.to_s
    else 
      (profile.member_role.to_s + ". " + profile.short_bio.to_s)
    end
  end

  def handle(link)
    File.basename(URI.parse(link).path) unless (link.nil? || link.empty?)
  end

  def create_user(wp_author, user_profile)
    puts "... Attempting to create new COMPEL user: " + wp_author.email

    user = User.new({email: wp_author.email})
    user.display_name = wp_author.display_name
    user.password = SecureRandom.uuid
    user.personal_statement = personal_statement(user_profile)
    user.twitter_handle = handle(user_profile.member_twitter_link)
    user.facebook_handle = handle(user_profile.member_facebook_link)
    user.googleplus_handle = handle(user_profile.member_google_link)
        
    if !( user_profile.member_website_link.nil? || user_profile.member_website_link.blank?)
      wlink = UserLink.find_or_create_by({link: user_profile.member_website_link})
      wlink.link = user_profile.member_website_link
      user.user_links << wlink
    end

    # TODO: Potentially add Soundcloud as a website (uncomment below)
    #       or add as new social media via LIBTD-1385
    #if !( user_profile.member_soundcloud_link.nil? || user_profile.member_soundcloud_link.blank?)
    #  slink = UserLink.find_or_create_by({link: user_profile.member_soundcloud_link})
    #  slink.link = user_profile.member_soundcloud_link
    #  user.user_links << slink
    #end

    begin
      # Initially try to save without the profile image
      user.save!
      puts "... User imported to COMPEL: "+user.inspect
    rescue ActiveRecord::RecordInvalid => ri_error
      puts "!!!!! User creation failed: " + ri_error.message
    end

    # Now, try to save the profile image url
    # If it fails, that's okay.
    # There are all sorts of reasons why this might fail:
    #   Image is larger than 2 MB
    #   Image doesn't exist, etc.
    user.remote_avatar_url = user_profile.member_profile_img_src
    begin
      user.save!
      puts "... User avatar uploaded to COMPEL."
    rescue ActiveRecord::RecordInvalid => ri_error
      puts "!!!!! User avatar upload failed: " + ri_error.message
    end
  end
end
