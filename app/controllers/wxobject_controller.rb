require 'digest/sha1'
require 'net/http'
require 'openssl'
require 'json'
require 'WxPicResponse'
require 'WxTextResponse'

class WxobjectController < ApplicationController
  #wrap_parameters :format=>:xml
  WX_TOKEN = "xhyt"
  

  def validate
    signature = params[:signature]
    encrypEcho = Digest::SHA1.hexdigest([WX_TOKEN,params[:timestamp],params[:nonce]].sort.join)
    logger.info "input:#{signature}, output:#{encrypEcho}"
    sign_result= params[:echostr] if signature==encrypEcho
    render :text=>sign_result
  end
  
  def search
    input = params[:xml]
    # choose response action based on params xml
    response_action = find_action_by_xml input
    # trigger action
    response = response_action.call input
    render :xml=>response.to_xml2
  end
  private
  def find_action_by_xml(input)
    case(input[:MsgType])
    when 'text' then
      input_text = input[:Content]
      input_text_array = input_text.split(' ')
      exist_auto_reply = WxReplyMsg.find_by_rkey_and_status(input_text,1)
      unless exist_auto_reply.nil?
        return proc {|h|
          response = WxTextResponse.new
          set_common_response response
          response.Content = exist_auto_reply.rmsg
          response
          } 
      end
      if input_text == 'Hello2BizUser'
        return method(:action_say_hello)
      elsif [t(:commandjf),'jd'].include? input_text
        return method(:action_point_bd)
      elsif [t(:commandbd),'bd'].include? input_text
        return method(:action_card_bd)
      elsif [t(:commandmore),'m'].include? input_text
        return method(:action_list_more)
      elsif 'yh'==input_text||input_text.include?(t(:commandpromotion))||input_text.include?(t(:commandpromotion2))
        return method(:action_list_promotion_ft)
      elsif t(:commanddh)==input_text
        return method(:action_msg_dh)
      elsif t(:commandpg)== input_text
        return method(:action_msg_pg)
      elsif [t(:commandhelp),'h','help'].include? input_text
        return method(:action_not_recognize)
      elsif /^\d+$/ =~ input_text_array[0]
        return method(:action_point_nb)
      else
         return method(:action_list_product_ft)
      end
    when 'location' then
      return method(:action_list_promotion_ft)
    when 'event' then
      event_type = input[:Event]
      if event_type == 'subscribe'
        return method(:action_say_hello)
      elsif event_type == 'click'
        event_key = input[:EventKey]
        if event_key == '100_EP'
          return method(:action_click_ep)
        end
      end
    else
      method(:action_not_recognize)
    end
  end
  def action_msg_dh(input)
    response = WxTextResponse.new
    set_common_response response
    response.Content = t :msg_dh
    response
  end
  def action_msg_pg(input)
    response = WxTextResponse.new
    set_common_response response
    response.Content = t :msg_pg
    response
  end
  def action_click_ep(input)
    token = params[:xml][:FromUserName]
    card_info = Card.where(:utoken=>token,:isbinded=>true).order('validatedate desc').first
    if !card_info.nil? && card_info[:validatedate]<Time.now
       card_info = Card.renew_card token
    end
    return build_response_text_temp {|msg|
                  msg.Content = t(:notbindinghelp)
             } if card_info.nil?
    #persist user request
    log_use_request {|request|
      request.lastaction = RequestAction::ACTION_EX_POINT
      }
    ex_result = Card.point_exchange card_info.no,10
    return build_response_text_temp do
      msg.Content = t(:exchangepointfail)
    end if !ex_result
    return build_response_text_temp {|msg|
      msg.Content = t(:exchangepointsuccess).sub('[amount]',10.to_s)
     }
  end
  #action search products first time
  def action_list_product_ft(input)
    response = do_list_product(input[:Content],1)
     #persist user request
    log_use_request {|request|
      request.lastaction = RequestAction::ACTION_PROD_LIST_FT
      request.lastpage = 1
      }
    response
  end
  
  #action search more product or promotion
  def action_list_more(input)
    # check whether last five mins search product or promotion success
    utoken = input[:FromUserName]
    lastrequest = UserRequest.where("utoken=:token AND updated_at>:validatetime AND lastaction IN (:product_ft_search,:promotion_ft_search)",{
        :token=>utoken,
        :validatetime => Time.now-5.minutes,
        :product_ft_search => RequestAction::ACTION_PROD_LIST_FT,
        :promotion_ft_search => RequestAction::ACTION_PRO_LIST_FT
    }).first
    return build_response_text_temp {|msg|
      msg.Content=t :noproductsearchhistory
    } if lastrequest.nil?
    lastpage = lastrequest[:lastpage]
    lastmsg = JSON.parse(lastrequest[:msg])
    if lastrequest[:lastaction] == RequestAction::ACTION_PROD_LIST_FT
      # do more search for product
      response = do_list_product(lastmsg["Content"],lastpage+1)
    else
      # do more search for promotion
      response = do_list_promotion lastmsg,lastpage+1
    end
    #persist user request
    lastrequest.lastpage = lastpage % 1000+1
    lastrequest.save
    response
  end
  # action to search point without card bindng
  def action_point_nb(input)
    input_text_array = input[:Content].split(' ')
    return build_response_text_temp {|msg|
        msg.Content = t(:wrongpwd)
      } if input_text_array.length <2
    card_info = Card.find_by_nopwd input[:FromUserName],input_text_array[0],input_text_array[1]
    #persist user request
    log_use_request {|request|
      request.lastaction = RequestAction::ACTION_JF_SEARCH_NB
      }
    return build_response_text_temp {|msg|
            msg.Content = t(:successmsgnotbindtemplate).sub('[level]',card_info[:level]).sub('[point]',card_info['point'].to_s)
          } if !card_info.nil?
    return build_response_text_temp {|msg|
            msg.Content = t(:wrongpwd)
            }
  end
  # action request to bind card
  def action_card_bd(input)
    utoken = params[:xml][:FromUserName]
    card_info = Card.where(:utoken=>utoken).order('validatedate desc').first
    return build_response_text_temp {|msg|
              msg.Content=t(:notbindinghelp)
          } if card_info.nil?
     card_info[:isbinded]=true
     card_info.save
     #persist user request
    log_use_request {|request|
      request.lastaction = RequestAction::ACTION_JF_BIND
      }
     return build_response_text_temp {|msg|
            msg.Content = t(:bindingsuccess)
          }
  end
  # action search point has binded
  def action_point_bd(input)
    token = params[:xml][:FromUserName]
    card_info = Card.where(:utoken=>token,:isbinded=>true).order('validatedate desc').first
    if !card_info.nil? && card_info[:validatedate]<Time.now
       card_info = Card.renew_card token
    end
    #persist user request
    log_use_request {|request|
      request.lastaction = RequestAction::ACTION_JF_SEARCH_BD
      }
    return build_response_text_temp {|msg|
      msg.Content = t(:successmsgtemplate).sub('[level]',card_info[:level]).sub('[point]',card_info['point'].to_s)
     } if !card_info.nil?

    return build_response_text_temp {|msg|
                  msg.Content = t(:notbindinghelp)
               }
  end
  # action say hello
  def action_say_hello(input)
    response = WxTextResponse.new
    set_common_response response
    response.Content = t :welcome
    response
  end
  # the action just render the not recognize message
  def action_not_recognize(input)
    response = WxTextResponse.new
    set_common_response response
    response.Content = t :commonhelp
    response
  end
  # action render the promotions first time
  def action_list_promotion_ft(input)
    response = do_list_promotion input,1
    #persist user request
    log_use_request {|request|
      request.lastaction = RequestAction::ACTION_PRO_LIST_FT
      request.lastpage = 1
      }
    response
  end
  
  def build_response_text_temp
    response = WxTextResponse.new
    set_common_response response
    yield response if block_given?
    response
  end
  def build_response_nofound
      response = build_response_text_temp do |msg|
        msg.Content = t :keynotfound
      end
      response     
  end
  def build_response_nolocation
      response = build_response_text_temp do |msg|
        msg.Content = t :locationnotfound
      end
      response     
  end
  def set_common_response(resp)
     resp.ToUserName=params[:xml][:FromUserName]
     resp.FromUserName=params[:xml][:ToUserName]
     resp.CreateTime=Time.now.to_i
     resp.MsgType='text'
     resp.FuncFlag=0
  end
  def do_list_promotion(input,nextpage)
    longit = input['Location_X']
    lantit = input['Location_Y']
     
    nextpage=1 if nextpage.nil?
    pagesize=9
    promotions = Promotion.search :per_page=>pagesize,:page=>nextpage do 
            query do
              match :status,1
            end
            filter :geo_distance,{
                    'distance' => "500000km",
                    'store.location' => {
                    'lat' => lantit,
                    'lon' => longit
                    }
              } unless longit.nil? || lantit.nil?
            filter :range,{
              'endDate' =>{
                'gte'=>Time.now
              }
            }
            sort {
            by :isTop, 'desc'
            by :createdDate, 'desc'
          }
    end
    #return not found message if no match
    return build_response_nofound if promotions.total<=0 || promotions.total<=(nextpage-1)*pagesize
    response = WxPicResponse.new
    set_common_response response
    response.MsgType = 'news'
    response.ArticleCount = promotions.results.length
    response.Articles = []   
    first_image = true
    promotions.results.each {|p|
      resource = p['resource']
      return if resource.nil? || resource.length<1 || resource[0].name.length<1
      
      item = WxPicArticle.new
      item.Title = "#{p['store']['name']}:#{p['name']}"
      item.Description = p['description']
      if first_image == true
        item.PicUrl =  large_pic_url resource[0].domain, resource[0].name
        first_image = false
      else
        item.PicUrl =  small_pic_url resource[0].domain, resource[0].name
      end
      item.Url = url_for :controller=>'promotion',:action=>'index',:id=>p[:id]
      response.Articles<<item
    }
     #add more indicator
    has_displayed = nextpage*pagesize
    if promotions.total>has_displayed
      item = WxPicArticle.new
      item.Title = t(:hasmoreresulttemp).sub('[currentcount]',has_displayed.to_s).sub('[totalcount]',promotions.total.to_s)
      item.Description = item.Title
      item.PicUrl = ''
      item.Url=response.Articles[0].Url
      response.Articles<<item
      response.ArticleCount +=1
    end
     response
  end
  def do_list_product(keyword,nextpage)
    # search products if msgtype is text and not a command
    nextpage = 1 if nextpage.nil?
    products = Product.search :per_page=>5,:page=>nextpage do 
            query do
              match ['*.name','*.description','*.engname','*.recommendreason'], keyword
              match :status,1
            end
          end
    #return not found message if no match
    return build_response_nofound if products.total<=0        
          
    response = WxPicResponse.new
    set_common_response response
    response.MsgType = "news"
    response.ArticleCount = products.results.length
    response.Articles = []
    response.FuncFlag= 0
    
    first_image = true
    products.results.each {|p|
      resource = p['resource']
      return if resource.nil? || resource.length<1 || resource[0].name.length<1
      item = WxPicArticle.new
      item.Title = "#{p['brand']['name']}:#{p['name']}"
      item.Description = p['brand']['name']
      pic_name = resource[0].name.encode(:xml=>:text)
      if first_image == true
        item.PicUrl =  large_pic_url resource[0].domain, pic_name
        first_image = false
      else
        item.PicUrl =  small_pic_url resource[0].domain, pic_name
      end
      item.Url = url_for :controller=>'product',:action=>'index',:id=>p[:id]
      response.Articles<<item
    }
    
    #add more indicator
    has_displayed = nextpage*5
    if products.total>has_displayed
      item = WxPicArticle.new
      item.Title = t(:hasmoreresulttemp).sub('[currentcount]',has_displayed.to_s).sub('[totalcount]',products.total.to_s)
      item.Description = item.Title
      item.PicUrl = ''
      item.Url=response.Articles[0].Url
      response.Articles<<item
      response.ArticleCount +=1
    end
    response
  end
  def log_use_request(token=params[:xml][:FromUserName])
    lastrequest = UserRequest.where(:utoken=>token).first
    if lastrequest.nil?
      lastrequest = UserRequest.new
      lastrequest.utoken = token
      lastrequest.lastpage = 1
    end
    lastrequest.msg = params[:xml].to_json
    yield lastrequest if block_given?
    lastrequest.save
  end
  def small_pic_url(domain,name)
    domain = PIC_DOMAIN 
    return domain + name +'_120x0.jpg'
  end
  def large_pic_url(domain,name)
    domain = PIC_DOMAIN
    return domain + name +'_640x0.jpg'
  end
end
