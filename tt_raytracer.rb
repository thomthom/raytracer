#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------

require 'sketchup.rb'
require 'TT_Lib2/core.rb'

TT::Lib.compatible?('2.3.0', 'TT Raytracer')

#-----------------------------------------------------------------------------

module TT::Plugins::Raytracer
  
  ### CONSTANTS ### --------------------------------------------------------
  
  PLUGIN_ID       = 'TT_Raytracer'.freeze
  PLUGIN_NAME     = 'Raytracer'.freeze
  PLUGIN_VERSION  = '1.2.0'.freeze
  
  # Version information
  RELEASE_DATE    = '29 Mar 12'.freeze
  
  
  ### MODULE VARIABLES ### -------------------------------------------------
  
  # Preference
  @settings = TT::Settings.new( PLUGIN_ID )
  @settings[:ray_stop_at_ground, false]
  @settings[:rayspray_number, 32]
  
  
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
    m.add_separator
    mnu = m.add_item('Rays Stops at Ground Plane') { self.toggle_ray_stop_at_ground }
    m.set_validation_proc(mnu) { vproc_ray_stop_at_ground }
  end
  
  
  ### LIB FREDO UPDATER ### ----------------------------------------------------
  
  def self.register_plugin_for_LibFredo6
    {   
      :name => PLUGIN_NAME,
      :author => 'thomthom',
      :version => PLUGIN_VERSION.to_s,
      :date => RELEASE_DATE,   
      :description => 'Freakkin rays with laserbeams!',
      :link_info => 'http://forums.sketchucation.com/viewtopic.php?t=30509'
    }
  end
  
  
  ### PROCS ### ------------------------------------------------------------
  
  def self.toggle_ray_stop_at_ground
    @settings[:ray_stop_at_ground] = !@settings[:ray_stop_at_ground]
  end
  
  def self.vproc_ray_stop_at_ground
    (@settings[:ray_stop_at_ground]) ? MF_CHECKED : MF_UNCHECKED
  end
  
  
  ### MAIN SCRIPT ### ------------------------------------------------------
  
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
  
  
  ### DEBUG ### ------------------------------------------------------------
  
  def self.reload
    load __FILE__
  end
  
end # module

#-----------------------------------------------------------------------------
file_loaded( __FILE__ )
#-----------------------------------------------------------------------------