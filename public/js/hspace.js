    var handler = null;
    var page = 1;
    var isLoading = false;
    var apiURL = 'http://stage.youhuiin.com/profile/get_list.json'
    
    // Prepare layout options.
    var options = {
      autoResize: true, // This will auto-update the layout when the browser window is resized.
      container: $('#tiles'), // Optional, used for some extra CSS styling
      offset: 2, // Optional, the distance between grid items
      itemWidth: 290 // Optional, the width of a grid item
    };
    
    /**
     * When scrolled all the way to the bottom, add more tiles.
     */
    function onScroll(event) {
      // Only check when we're not still waiting for data.
      if(!isLoading) {
        // Check if we're within 100 pixels of the bottom edge of the broser window.
        var closeToBottom = ($(window).scrollTop() + $(window).height() > $(document).height() - 100);
        if(closeToBottom) {
          loadData(loveType);
        }
      }
    };
    
    /**
     * Refreshes the layout.
     */
    function applyLayout() {
      // Clear our previous layout handler.
      if(handler) handler.wookmarkClear();
      
      // Create a new layout handler.
      handler = $('#tiles li');
      handler.wookmark(options);
    };
    
    /**
     * Loads data from the API.
     */
    function loadData($type) {
      isLoading = true;
	  loveType = $type;
      $('#loaderCircle').show();
      
      $.ajax({
        url: apiURL,
        dataType: 'jsonp',
        data: {page: page,loveType:loveType}, // Page parameter to make sure we load new data
        success: onLoadData
      });
    };
    
    /**
     * Receives data from the API, creates HTML for images and updates the layout
     */
    function onLoadData(data) {
      isLoading = false;
      $('#loaderCircle').hide();
      
      // Increment page index for future calls.
      page++;
      
      // Create HTML for the images.
     var html = '';
      var i=0, length=data.datas.length;
      for(; i<length; i++) {
       html+='<li>';
						html+='<div class="thumbnail">';
							html+='<div class="action">';
								html+='<a href="product.html"><img src="'+data.datas[i].imageUrl+'" alt="'+data.datas[i].imageUrl+'"></a>';
								html+='<span class="like"><i class="icon-heart icon-white"></i>'+data.datas[i].likeCount+'+</span>';
							html+='</div>';
							html+='<h4><a href="product.html">'+data.datas[i].title+'</a></h4>';
							html+='<small><span class="pull-left num">吊牌价：<em>￥'+data.datas[i].originalPrice+'</em></span><span class="pull-right price">销售价：<em>￥'+data.datas[i].price+'</em></span></small>';
						html+='</div>';
					html+='</li>';
      }
      
      // Add image HTML to the page.
      $('#space_list').append(html);
      
      // Apply layout.
      applyLayout();
    };
  
    $(document).ready(new function() {
      // Capture scroll event.
      $(document).bind('scroll', onScroll);
      
      // Load first data from the API.
      loadData('1');
    });