#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------

require 'sketchup.rb'
begin
  require 'TT_Lib2/core.rb'
rescue LoadError => e
  module TT
    if @lib2_update.nil?
      url = 'http://www.thomthom.net/software/sketchup/tt_lib2/errors/not-installed'
      options = {
        :dialog_title => 'TT_Lib² Not Installed',
        :scrollable => false, :resizable => false, :left => 200, :top => 200
      }
      w = UI::WebDialog.new( options )
      w.set_size( 500, 300 )
      w.set_url( "#{url}?plugin=#{File.basename( __FILE__ )}" )
      w.show
      @lib2_update = w
    end
  end
end


#-------------------------------------------------------------------------------

if defined?( TT::Lib ) && TT::Lib.compatible?( '2.7.0', 'Raytracer' )

module TT::Plugins::Raytracer

  
  ### MODULE VARIABLES ### -------------------------------------------------
  
  # Preference
  @settings = TT::Settings.new( PLUGIN_ID )
  @settings.set_default(:ray_stop_at_ground, false)
  @settings.set_default(:rayspray_number, 32)
  
  
  ### MENU & TOOLBARS ### --------------------------------------------------
  
  unless file_loaded?( __FILE__ )
    m = TT.menu('Plugins').add_submenu('Raytracer')
    m.add_item('Drop CPoints')                  { self.drop_cpoints }
    m.add_item('Drop CPoints (Trace)')          { self.drop_cpoints(true) }
    m.add_separator
    m.add_item('Drop Components')               { self.drop_instances }
    m.add_item('Drop Components by Bounds')     { self.drop_instances_by_bounds }
    m.add_item('Drop Components by Geometry (WIP)')   { self.drop_instances_by_geom }
    m.add_separator
    m.add_item('Grow Components from CPoints')  { self.grow_instances_from_cpoints_ui }
    m.add_separator
    m.add_item('Trace Ray Spray from CPoints')  { self.spray_raytrace }
    m.add_item('Spraycan')  { self.spray }
    m.add_separator
    mnu = m.add_item('Rays Stops at Ground Plane') { self.toggle_ray_stop_at_ground }
    m.set_validation_proc(mnu) { vproc_ray_stop_at_ground }
  end
  
  
  ### PROCS ### ------------------------------------------------------------
  
  def self.toggle_ray_stop_at_ground
    @settings[:ray_stop_at_ground] = !@settings[:ray_stop_at_ground]
  end
  
  def self.vproc_ray_stop_at_ground
    (@settings[:ray_stop_at_ground]) ? MF_CHECKED : MF_UNCHECKED
  end
  
  
  ### MAIN SCRIPT ### ------------------------------------------------------
  
  # http://www.anderswallin.net/2009/05/uniform-random-points-in-a-circle-using-polar-coordinates/
  #
  # @since 1.2.0
  def self.spray
    
    # Selected components will be used for spraying.
    
    # === Toolbar ===
    # 
    # Spray Tool
    # -----
    # Flood (Toggle)
    # Stack (Toggle)
    # Random Size (Toggle)
    # Filter (Toggle)
    # -----
    # Settings
    
    # === Settings ===
    # Target Layer
    # Filter Layer
    
    # === VCB ===
    # Radius
    # Pressure


    model = Sketchup.active_model
    instances = model.selection.select { |e| TT::Instance.is?(e) }

    if instances.empty?
      UI.messagebox( 'Select one or more group or component.' )
      return false
    end
    
    definitions = instances.map { |i| TT::Instance.definition(i) }.uniq
    model.select_tool( SprayCan.new(definitions) )
  end
  
  # @since 1.2.0
  class SprayCan
    
    def initialize(definitions)
      @definitions = definitions

      @ip_mouse = Sketchup::InputPoint.new
      
      @pick = nil
      @mouse_ray = nil
      @mouse_points = []
      
      @ray = nil
      @normal = Z_AXIS
      @points = []
      @radius = 20.m
      
      @mouse_down_time = nil
      @last_spray = nil
      
      @timer = nil
    end
    
    def resume( view )
      view.invalidate
      update_ui()
    end
    
    def activate
      update_ui()
    end
    
    def deactivate( view )
      view.invalidate
    end
    
    def update_ui
      Sketchup.vcb_label = 'Radius'
      Sketchup.vcb_value = @radius 
    end
    
    def enableVCB?
      return true
    end
    
    def onUserText( text, view )
      radius = text.to_l
    rescue
      radius = @radius
    ensure
      @radius = radius
      @source_point = @pick_point.offset( @normal, @radius * 2 )
      view.invalidate
      update_ui()
    end
    
    def onLButtonDown( flags, x, y, view )
      @mouse_down_time = Time.now
      squeeze( view )
      #@timer = UI.start_timer( 0.1, true ) {
      #  do_spray( view )
      #}
    end
    
    def squeeze( view )
      diff = Time.now - @mouse_down_time
      time_to_max = 3.0
      interval_max = 0.01
      interval_min = 0.1
      interval_diff = interval_min - interval_max
      ratio = interval_min - ( diff / time_to_max ) * interval_diff # 0.1 - 0.01
      #ratio = 0.1 - ( diff / time_to_max ) * 0.09 # 0.1 - 0.01
      
      if !@timer || diff < time_to_max
        UI.stop_timer( @timer ) if @timer
        @timer = UI.start_timer( ratio, true ) {
          squeeze( view )
        }
      end
      
      do_spray( view )
    end
    
    def do_spray( view )
      if @ray
        @last_spray = Time.now
        @mouse_points = trace_spray( @ray, @radius, view, false )
        @points.concat( @mouse_points )
        view.invalidate
      end
    end
    
    def onLButtonUp( flags, x, y, view )
      UI.stop_timer( @timer ) if @timer
      @mouse_points.clear
      @mouse_down_time = nil

      size = @definitions.size
      TT::Model.start_operation('Spraycan')
      for point in @points
        index = rand(size)
        definition = @definitions[index]
        tr = Geom::Transformation.new( point )
        view.model.active_entities.add_instance( definition, tr )
      end
      view.model.commit_operation
      @points.clear

      view.invalidate
    end
    
    def onMouseMove( flags, x, y, view )
      #@ip_mouse.pick( view, x, y )
      
      #@mouse_points.clear
      
      @mouse_ray = view.pickray( x, y )
      @pick = view.model.raytest( @mouse_ray  )
      
      if @pick
        
        # Pick ray normal.
        if flags & CONSTRAIN_MODIFIER_MASK == 0
          pick_path = @pick[1]
          entity = pick_path.pop
          if entity.is_a?( Sketchup::Face )
            transformation = Geom::Transformation.new
            for e in pick_path
              next unless e.respond_to?( :transformation )
              transformation *= e.transformation
            end
            @normal = entity.normal.transform( transformation )
          else
            @normal = Z_AXIS
          end
        end
        
        # Calculate spray ray.
        @pick_point = @pick[0]
        @source_point = @pick_point.offset( @normal, @radius * 2 )
        #@ray = [ @source_point, @normal.reverse ]
        vector = @source_point.vector_to( @pick_point )
        @ray = [ @source_point, vector ]
        
        #@mouse_points = trace_spray( @ray, @radius, view, false )
      end
      
      # Add points to stack if mouse button is held.
      if flags & MK_LBUTTON == MK_LBUTTON
        diff = Time.now - @last_spray
        if diff > 0.1
          @mouse_points = trace_spray( @ray, @radius, view, false )
          @points.concat( @mouse_points )
        end
      end
      
      view.invalidate
      #view.refresh
    end
    
    def draw( view )
      if @ip_mouse.display?
        @ip_mouse.draw( view )
      end
      
      if @pick
        pt1 = @pick[0]
        #size = view.pixels_to_model( 100, pt1 )
        #pt2 = pt1.offset( Z_AXIS, size )
        pt2 = pt1.offset( @normal, @radius * 2 )
        
        points = [ @source_point, @pick_point ]
        circle = TT::Geom3d.circle( @pick_point, @normal, @radius, 48 )
        
        12.times { |i|
          points << @source_point
          points << circle[i*4]
        }
        
        view.line_stipple = '-'
        view.line_width = 1
        view.drawing_color = [255,128,0]
        view.draw( GL_LINES, points )
        
        view.line_stipple = ''
        view.draw( GL_LINE_LOOP, circle )
        view.drawing_color = [255,128,0,26]
        view.draw( GL_POLYGON, circle )
      end
      
      if @pick_point
        view.line_stipple = ''
        view.line_width = 2
        view.draw_points( @pick_point, 8, 4, 'purple' )
      end
      
      if @source_point
        view.line_stipple = ''
        view.line_width = 2
        view.draw_points( @source_point, 8, 4, 'blue' )
      end 
      
      unless @mouse_points.empty?
        view.line_stipple = ''
        view.line_width = 2
        view.draw_points( @mouse_points, 6, 3, [128,255,0] )
        
        pts = @mouse_points.map { |pt| [ @source_point, pt ] }.flatten
        view.line_width = 1
        view.drawing_color = [0,0,255]
        view.draw( GL_LINES, pts )
      end
      
      unless @points.empty?
        view.line_stipple = ''
        view.line_width = 2
        view.draw_points( @points, 6, 3, [255,0,0] )
      end
    end

    
    def trace_spray( ray, radius, view, uniform = true, density = 2 )
      points = []
      source, direction = ray
      target = source.offset( direction )
      tr = Geom::Transformation.new( target, direction )
      density.times {
        #x, y, z = target.to_a
        angle = rand() * 2 * Math::PI
        if uniform
          random_radius = radius * Math.sqrt( rand() )
        else
          random_radius = radius * rand()
        end
        x = random_radius * Math.sin( angle )
        y = random_radius * Math.cos( angle )
        random_point = Geom::Point3d.new( x, y, 0 )
        random_point.transform!( tr )

        #current_ray = [ random_point, direction ]
        current_ray = [ source, random_point ]
        result = view.model.raytest( current_ray )
        next unless result
        points << result[0]
      }
      points
    end
    
  end
  
  
  
  # Spray Trace Rays from CPoints
  # Shoots N given number of rays from each selected CPoint and generates groups
  # of CLines and CPoints tracing the rays that hit any entities.
  def self.spray_raytrace
    # Prompt user for input
    prompts = [ 'Number of Rays: ' ]
    defaults = [ @settings[:rayspray_number] ]
    result = UI.inputbox( prompts, defaults, 'Trace Ray Spray' )
    return if result == false
    
    number_of_points = result[0]
    
    if number_of_points > 10000
      result = UI.messagebox( "#{number_of_points} rays per point, are you mad!?", MB_YESNO )
      if result == IDNO
        return
      else
        UI.messagebox('Good Luck!')
      end
    end
    
    @settings[:rayspray_number] = number_of_points
  
    model = Sketchup.active_model
    TT::Model.start_operation('Trace Ray Spray from CPoints')
    
    # UI feedback statistic
    i = 0
    j = model.selection.length
    
    for entity in model.selection
      Sketchup.status_text = "Tracing CPoint #{i} of #{j}..."
      next unless entity.is_a?(Sketchup::ConstructionPoint)
      
      origin = entity.position
      
      pts = TT::Geom3d.spiral_sphere( number_of_points, origin )
      
      g = nil
      pts.each { |pt|
        ray = TT::Ray.new( origin, pt )
        result = ray.test( model, @settings[:ray_stop_at_ground] )
        next if result.nil?
        
        point = result[0]
        
        g ||= model.active_entities.add_group
        g.entities.add_cpoint(point)
        g.entities.add_cline(origin, point)
      }
    end
    
    model.commit_operation
    Sketchup.status_text = 'Done!'
  end
  
  
  # Traces selected CPoints down to the ground. If -trace- is true a CLine and
  # CPoint is added to visual the ray - if false it moves the existing CPoint.
  def self.drop_cpoints(trace = false)
    model = Sketchup.active_model
    TT::Model.start_operation('Drop CPoint')
    
    # UI feedback statistic
    i = 0
    j = model.selection.length
    
    for entity in model.selection
      Sketchup.status_text = "Dropping CPoints #{i} of #{j}..."
      next unless entity.is_a?(Sketchup::ConstructionPoint)
      
      cpoint = entity.position
      
      ray = TT::Ray.new( cpoint, Z_AXIS.reverse )
      result = ray.test( model, @settings[:ray_stop_at_ground] )
      next if result.nil?
      
      point = result[0]
      
      if trace
        model.active_entities.add_cpoint(point)
        model.active_entities.add_cline(cpoint, point)
      else
        model.active_entities.transform_by_vectors( [entity], [cpoint.vector_to(point)] )
      end
    end
    
    model.commit_operation
    Sketchup.status_text = 'Done!'
  end
  
  
  # Drops selected instances down to the surface below using the insertion point.
  def self.drop_instances
    model = Sketchup.active_model
    sel = model.selection
    
    TT::Model.start_operation('Drop Instances')
    entities = []
    vectors = []
    sel.each { |e|
      next unless TT::Instance.is?( e )
      pt = e.transformation.origin
      ray = TT::Ray.new( pt, Z_AXIS.reverse )
      result = ray.test( model, @settings[:ray_stop_at_ground] )
      next if result.nil?
      entities << e
      vectors << pt.vector_to( result[0] )
    }
    model.active_entities.transform_by_vectors( entities, vectors )
    model.commit_operation
  end
  
  
  # (!) Account for 2D components
  # Drops selected instances down to the surface below using the bottom corners
  # of the boundingbox.
  def self.drop_instances_by_bounds
    model = Sketchup.active_model
    sel = model.selection
    
    TT::Model.start_operation('Drop Instances by Bounds')
    sel.each { |e|
      next unless TT::Instance.is?( e )
      
      # Create a set of world points for the BB box and raytrace down.
      bb_pts = []
      ray_pts = []
      (0..3).each { |i|
        d = TT::Instance.definition(e)
        pt = d.bounds.corner(i).transform( e.transformation )
        
        ray = TT::Ray.new( pt, Z_AXIS.reverse )
        result = ray.test( model, @settings[:ray_stop_at_ground] )
        next if result.nil?
        
        bb_pts << pt
        ray_pts << result[0]
        
        #model.active_entities.add_cline(pt, ray_pts.last)
        #model.active_entities.add_cpoint(pt)
        #model.active_entities.add_cpoint(ray_pts.last)
      }
      #next unless pts.length >= 3
      next unless bb_pts.length == 4
      
      # Calculate ground plane.
      plane = Geom.fit_plane_to_points( ray_pts )
      
      # Project points to the plane which now is the new ground.
      p_pts = bb_pts.map { |pt|
        line = [ pt, Z_AXIS.reverse ]
        Geom.intersect_line_plane( line, plane )
      }
      
      # Calculate X vectors for bounding box and new ground vector.
      vx1 = bb_pts[0].vector_to( bb_pts[1] )
      vx2 = p_pts[0].vector_to( p_pts[1] )
      # Calculate X rotation axis
      vx = vx1 * vx2
      vx = vx1.axes.y unless vx.valid?
      
      # Calculate Y vectors for bounding box and new ground vector.
      vy1 = bb_pts[0].vector_to( bb_pts[2] )
      vy2 = p_pts[0].vector_to( p_pts[2] )
      # Calculate y rotation axis
      vy = vy1 * vy2
      vy = vy1.axes.x unless vy.valid?
      
      # Calculate the angles to use later on to orient the instance
      # to the ground.
      ax = vx1.angle_between( vx2 )
      ay = vy1.angle_between( vy2 )
      
      # Calculate the offsetting distance of the instance to the new
      # location on ground.
      org_pt = e.transformation.origin
      line = [ org_pt, Z_AXIS.reverse ]
      ray_pt = Geom.intersect_line_plane( line, plane )
      offset = org_pt.vector_to( ray_pt )
      
      # Move, Rotate X, Rotate Y
      tt = Geom::Transformation.translation( offset )
      tx = Geom::Transformation.rotation( ray_pt, vx, ax )
      ty = Geom::Transformation.rotation( ray_pt, vy, ay )
      t = tx * ty * tt
      
      # (?) Bulk transformation? Speed improvement?
      e.transform!( t )
    }
    model.commit_operation
  end
  
  
  # (!) WIP
  def self.drop_instances_by_geom
    model = Sketchup.active_model
    sel = model.selection
    stop_at_ground = @settings[:ray_stop_at_ground]
    down = Z_AXIS.reverse
    
    TT::Model.start_operation('Drop Instances by Geometry')
    sel.each { |i|
      next unless TT::Instance.is?( i )
      
      # Gather vertices
      d = TT::Instance.definition(i)
      pts = TT::Entities.positions(d.entities, i.transformation)
      
      # Raytrace down to ground - ignore vertices that hits self.
      rays = []
      pts.each { |pt|
        # Shoot a ray downwards to the ground.
        ray = TT::Ray.new( pt, down )
        test = ray.test( model, stop_at_ground )
        # Ignore if it hits nothing.
        next if test.nil?
        # Ignore it it hits self.
        next if test[1].include?(i)
        
        ray_pt = test[0]
        rays << [pt, ray_pt, pt.distance(ray_pt)] # (!) Custom struct.
        
        # <debug>
        model.active_entities.add_cline(pt, ray_pt)
        model.active_entities.add_cpoint(pt)
        model.active_entities.add_cpoint(ray_pt)
        # </debug>
      } # pts
      
      # Need at least three points to calculate a plane to position the
      # component on.
      next if rays.length < 3
      
      # Sort rays by their length
      rays.sort!{ |x,y| x[2] <=> y[2] }
      
      #rays.each { |r| p r }
      
      # 1. Get lowest offset pt (pt1)
      # 2. Get point furthest from pt1 (pt2)
      # 3. Get point furthest from pt1 and pt2 (pts3)
      
      p1 = rays[0][1]
      p2 = rays[1][1]
      p3 = nil
      line = [p1, p2]
      (2...rays.length).each { |n|
        next if rays[n][1].on_line?( line )
        p3 = rays[n][1]
        break
      }
      next if p3.nil?
      
      plane = Geom.fit_plane_to_points( p1, p2, p3 )
      
      model.active_entities.add_curve( p1, p2, p3 )
      
      
      ray_points = rays.map { |r| r[1] }
      #best_fit_plane = Geom.fit_plane_to_points( ray_points )
      
      #for point in ray_points
      #  #pt = point.project_to_plane( best_fit_plane )
      #  pt = point.project_to_plane( plane )
      #  model.active_entities.add_cpoint(pt)
      #end
      
=begin
      # Try best fit plane. Check plane solutions and find the one where the
      # vertices are closest to the plane.
      ray_points = rays.map { |r| r[1] }
      deviation = self.deviance( points, plane )
      best_plane = plane
      plane_pts = []
      for pt in ray_points
        plane_pts << pt
        plane = Geom.fit_plane_to_points( plane_pts )
        test_deviation = self.deviance( points, plane )
        if deviation.nil? || test_deviation < deviation
          best_plane = plane
          deviation = test_deviation
        elsif !deviation.nil?
          # Last plane was no better - remove from set
          plane_pts.pop
        end
      end
=end

      
    } # sel
    model.commit_operation
  end
  
  
  def self.deviance( points, plane )
    length = 0
    for point in points
      point_on_plane = point.project_to_plane( plane )
      length += point.distance( point_on_plane )
    end
    length
  end
  
  
  # Trace CPoint from given layers down to the surface below and inserts
  # selected components at the ground point, scaling up to the original CPoint.
  def self.grow_instances_from_cpoints_ui
    model = Sketchup.active_model
    sel = model.selection
    
    # Get set of components to insert
    comps = []
    sel.each { |e|
      comps << TT::Instance.definition(e) if TT::Instance.is?(e)
    }
    comps.uniq!
    
    if comps.empty?
      UI.messagebox('No Instances selected. Select at least one.')
      return
    end
    
    # Get default values
    d_filter  = @settings[:grow_layers, '6113']
    d_min     = @settings[:grow_min_height, 5.m]
    d_max     = @settings[:grow_max_height, 15.m]
    
    # Get user input
    prompts = [
      'Layers Filter: ',
      'Default Minimum Size: ',
      'Default Maximum Size: ',
      'Put on Layer: '
    ]
    defaults = [d_filter, d_min, d_max, model.active_layer.name]
    list = ['', '', '', model.layers.map{|l|l.name}.join('|')]
    result = UI.inputbox(prompts, defaults, list, 'Grow Components from CPoints')
    return if result == false
    
    # Process user input
    filter, size_min, size_max, layer = result
    @settings[:grow_layers] = filter
    @settings[:grow_min_height] = size_min
    @settings[:grow_max_height] = size_max
    filter = filter.split(',').map{|f|f.strip}.join('|') # Convert , to | and remove whitespace
    default_size = [size_min, size_max]
    layer = model.layers[layer]
    layers = model.layers.select { |l| !l.name.match(filter).nil? }
    
    # (!) If selected, run on selected comp/group - otherwise, process whole model.
    # Insert Components
    TT::Model.start_operation('Grow Instances from CPoint')
    options = {
      :size => default_size,
      :ground => @settings[:ray_stop_at_ground],
      :layer => layer
    }
    self.grow_instances_from_cpoints(model.entities, layers, comps, options)
    model.commit_operation
  end
  
  def self.grow_instances_from_cpoints(entities, layers, comps, options, path = [])
    # Ensure we don't process the components we insert.
    comps.each { |comp|
      return if comp.entities == entities # (?)
    }
    size = options[:size]
    
    instances = []
    model = Sketchup.active_model
    entities.each { |e|
      if TT::Instance.is?( e )
        # Recursive processing of child instances.
        new_path = path.dup << e
        ents = TT::Instance.definition( e ).entities
        self.grow_instances_from_cpoints(ents, layers, comps, options, new_path)
      else
        # Process CPoints
        next unless layers.include?(e.layer) && e.is_a?(Sketchup::ConstructionPoint)
        gp = e.position # Global Point
        path.each { |x| gp.transform!(x.transformation) }
        
        # Raytrace the point
        ray = TT::Ray.new(gp, Z_AXIS.reverse)
        pt, ray_path = ray.test( model, options[:ground] )
        next if pt.nil?
        
        # The ray hit the surface, pick one of the component definitions and
        # place an instance between the surface and the CPoint
        comp = comps[ rand(comps.length) ]
        scale = 1.0
        if !pt.nil? && ( d = gp.distance(pt) ) > 0.0
          # The point is the top of the comp - we measure the distance down to the ground
          scale = d / comp.bounds.depth
        else
          # The point is from the ground, so we generate a random size.
          d = size[0] + rand(size[1] - size[0])
          scale = d / comp.bounds.depth
        end
        # Generate the transformation and add the instance.
        pt = gp if pt.nil?
        ts = Geom::Transformation.scaling(scale, scale, scale) # Account for SU7.1 bug
        tt = Geom::Transformation.new( pt )
        t = tt * ts
        # Keep the instances in an array to prevent them affecting the next raytrace.
        instances << [comp, t]
      end
    }
    instances.each { |c, t|
      instance = model.active_entities.add_instance(c, t)
      instance.layer = options[:layer]
    }
  end
  
  
  ### DEBUG ### ----------------------------------------------------------------
  
  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::Template.reload
  #
  # @param [Boolean] tt_lib Reloads TT_Lib2 if +true+.
  #
  # @return [Integer] Number of files reloaded.
  # @since 1.0.0
  def self.reload( tt_lib = false )
    original_verbose = $VERBOSE
    $VERBOSE = nil
    TT::Lib.reload if tt_lib
    # Core file (this)
    load __FILE__
    # Supporting files
    if defined?( PATH ) && File.exist?( PATH )
      x = Dir.glob( File.join(PATH, '*.{rb,rbs}') ).each { |file|
        load file
      }
      x.length + 1
    else
      1
    end
  ensure
    $VERBOSE = original_verbose
  end

end # module

end # if TT_Lib

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------