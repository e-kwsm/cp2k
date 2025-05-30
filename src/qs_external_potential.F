!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Routines to handle an external electrostatic field
!>        The external field can be generic and is provided by user input
! **************************************************************************************************
MODULE qs_external_potential
   USE atomic_kind_types,               ONLY: atomic_kind_type,&
                                              get_atomic_kind
   USE cell_types,                      ONLY: cell_type,&
                                              pbc
   USE cp_control_types,                ONLY: dft_control_type
   USE cp_log_handling,                 ONLY: cp_to_string
   USE cp_realspace_grid_cube,          ONLY: cp_cube_to_pw
   USE force_fields_util,               ONLY: get_generic_info
   USE fparser,                         ONLY: evalf,&
                                              evalfd,&
                                              finalizef,&
                                              initf,&
                                              parsef
   USE input_section_types,             ONLY: section_vals_get_subs_vals,&
                                              section_vals_type,&
                                              section_vals_val_get
   USE kinds,                           ONLY: default_path_length,&
                                              default_string_length,&
                                              dp,&
                                              int_8
   USE maxwell_solver_interface,        ONLY: maxwell_solver
   USE message_passing,                 ONLY: mp_comm_type
   USE particle_types,                  ONLY: particle_type
   USE pw_grid_types,                   ONLY: PW_MODE_LOCAL
   USE pw_methods,                      ONLY: pw_zero
   USE pw_types,                        ONLY: pw_r3d_rs_type
   USE qs_energy_types,                 ONLY: qs_energy_type
   USE qs_environment_types,            ONLY: get_qs_env,&
                                              qs_environment_type
   USE qs_force_types,                  ONLY: qs_force_type
   USE qs_kind_types,                   ONLY: get_qs_kind,&
                                              qs_kind_type
   USE string_utilities,                ONLY: compress
#include "./base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_external_potential'

! *** Public subroutines ***
   PUBLIC :: external_e_potential, &
             external_c_potential

CONTAINS

! **************************************************************************************************
!> \brief  Computes the external potential on the grid
!> \param qs_env ...
!> \date   12.2009
!> \author Teodoro Laino [tlaino]
! **************************************************************************************************
   SUBROUTINE external_e_potential(qs_env)

      TYPE(qs_environment_type), POINTER                 :: qs_env

      CHARACTER(len=*), PARAMETER :: routineN = 'external_e_potential'

      INTEGER                                            :: handle, i, j, k
      INTEGER(kind=int_8)                                :: npoints
      INTEGER, DIMENSION(2, 3)                           :: bo_global, bo_local
      REAL(kind=dp)                                      :: dvol, scaling_factor
      REAL(kind=dp), ALLOCATABLE, DIMENSION(:)           :: efunc, grid_p_i, grid_p_j, grid_p_k
      REAL(kind=dp), ALLOCATABLE, DIMENSION(:, :)        :: grid_p
      REAL(kind=dp), DIMENSION(3)                        :: dr
      TYPE(dft_control_type), POINTER                    :: dft_control
      TYPE(pw_r3d_rs_type), POINTER                      :: v_ee
      TYPE(section_vals_type), POINTER                   :: ext_pot_section, input

      CALL timeset(routineN, handle)
      CALL get_qs_env(qs_env, dft_control=dft_control)
      IF (dft_control%apply_external_potential) THEN
         IF (dft_control%eval_external_potential) THEN
            CALL get_qs_env(qs_env, vee=v_ee)
            IF (dft_control%expot_control%maxwell_solver) THEN
               scaling_factor = dft_control%expot_control%scaling_factor
               CALL maxwell_solver(dft_control%maxwell_control, v_ee, &
                                   qs_env%sim_step, qs_env%sim_time, &
                                   scaling_factor)
               dft_control%eval_external_potential = .FALSE.
            ELSEIF (dft_control%expot_control%read_from_cube) THEN
               scaling_factor = dft_control%expot_control%scaling_factor
               CALL cp_cube_to_pw(v_ee, 'pot.cube', scaling_factor)
               dft_control%eval_external_potential = .FALSE.
            ELSE
               CALL get_qs_env(qs_env, input=input)
               ext_pot_section => section_vals_get_subs_vals(input, "DFT%EXTERNAL_POTENTIAL")

               dr = v_ee%pw_grid%dr
               dvol = v_ee%pw_grid%dvol
               CALL pw_zero(v_ee)

               bo_local = v_ee%pw_grid%bounds_local
               bo_global = v_ee%pw_grid%bounds

               npoints = INT(bo_local(2, 1) - bo_local(1, 1) + 1, kind=int_8)* &
                         INT(bo_local(2, 2) - bo_local(1, 2) + 1, kind=int_8)* &
                         INT(bo_local(2, 3) - bo_local(1, 3) + 1, kind=int_8)
               ALLOCATE (efunc(npoints))
               ALLOCATE (grid_p(3, npoints))
               ALLOCATE (grid_p_i(bo_local(1, 1):bo_local(2, 1)))
               ALLOCATE (grid_p_j(bo_local(1, 2):bo_local(2, 2)))
               ALLOCATE (grid_p_k(bo_local(1, 3):bo_local(2, 3)))

               DO i = bo_local(1, 1), bo_local(2, 1)
                  grid_p_i(i) = (i - bo_global(1, 1))*dr(1)
               END DO
               DO j = bo_local(1, 2), bo_local(2, 2)
                  grid_p_j(j) = (j - bo_global(1, 2))*dr(2)
               END DO
               DO k = bo_local(1, 3), bo_local(2, 3)
                  grid_p_k(k) = (k - bo_global(1, 3))*dr(3)
               END DO

               npoints = 0
               DO k = bo_local(1, 3), bo_local(2, 3)
                  DO j = bo_local(1, 2), bo_local(2, 2)
                     DO i = bo_local(1, 1), bo_local(2, 1)
                        npoints = npoints + 1
                        grid_p(1, npoints) = grid_p_i(i)
                        grid_p(2, npoints) = grid_p_j(j)
                        grid_p(3, npoints) = grid_p_k(k)
                     END DO
                  END DO
               END DO

               DEALLOCATE (grid_p_i, grid_p_j, grid_p_k)

               CALL get_external_potential(grid_p, ext_pot_section, func=efunc)

               npoints = 0
               DO k = bo_local(1, 3), bo_local(2, 3)
                  DO j = bo_local(1, 2), bo_local(2, 2)
                     DO i = bo_local(1, 1), bo_local(2, 1)
                        npoints = npoints + 1
                        v_ee%array(i, j, k) = v_ee%array(i, j, k) + efunc(npoints)
                     END DO
                  END DO
               END DO

               DEALLOCATE (grid_p, efunc)

               dft_control%eval_external_potential = .FALSE.
            END IF
         END IF
      END IF
      CALL timestop(handle)
   END SUBROUTINE external_e_potential

! **************************************************************************************************
!> \brief  Computes the force and the energy due to the external potential on the cores
!> \param qs_env ...
!> \param calculate_forces ...
!> \date   12.2009
!> \author Teodoro Laino [tlaino]
! **************************************************************************************************
   SUBROUTINE external_c_potential(qs_env, calculate_forces)

      TYPE(qs_environment_type), POINTER                 :: qs_env
      LOGICAL, OPTIONAL                                  :: calculate_forces

      CHARACTER(len=*), PARAMETER :: routineN = 'external_c_potential'

      INTEGER                                            :: atom_a, handle, iatom, ikind, natom, &
                                                            nkind, nparticles
      INTEGER, DIMENSION(:), POINTER                     :: list
      LOGICAL                                            :: my_force, pot_on_grid
      REAL(KIND=dp)                                      :: ee_core_ener, zeff
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:)           :: efunc
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:, :)        :: dfunc, r
      TYPE(atomic_kind_type), DIMENSION(:), POINTER      :: atomic_kind_set
      TYPE(cell_type), POINTER                           :: cell
      TYPE(dft_control_type), POINTER                    :: dft_control
      TYPE(particle_type), DIMENSION(:), POINTER         :: particle_set
      TYPE(pw_r3d_rs_type), POINTER                      :: v_ee
      TYPE(qs_energy_type), POINTER                      :: energy
      TYPE(qs_force_type), DIMENSION(:), POINTER         :: force
      TYPE(qs_kind_type), DIMENSION(:), POINTER          :: qs_kind_set
      TYPE(section_vals_type), POINTER                   :: ext_pot_section, input

      CALL timeset(routineN, handle)
      NULLIFY (dft_control)

      CALL get_qs_env(qs_env=qs_env, &
                      atomic_kind_set=atomic_kind_set, &
                      qs_kind_set=qs_kind_set, &
                      energy=energy, &
                      particle_set=particle_set, &
                      input=input, &
                      cell=cell, &
                      dft_control=dft_control)

      IF (dft_control%apply_external_potential) THEN
         !ensure that external potential is loaded to grid
         IF (dft_control%eval_external_potential) THEN
            CALL external_e_potential(qs_env)
         END IF
         my_force = .FALSE.
         IF (PRESENT(calculate_forces)) my_force = calculate_forces
         ee_core_ener = 0.0_dp
         nkind = SIZE(atomic_kind_set)

         !check if external potential on grid has been loaded from a file instead of giving a function
         IF (dft_control%expot_control%read_from_cube .OR. &
             dft_control%expot_control%maxwell_solver) THEN
            CALL get_qs_env(qs_env, vee=v_ee)
            pot_on_grid = .TRUE.
         ELSE
            pot_on_grid = .FALSE.
            ext_pot_section => section_vals_get_subs_vals(input, "DFT%EXTERNAL_POTENTIAL")
         END IF

         nparticles = 0
         DO ikind = 1, SIZE(atomic_kind_set)
            CALL get_atomic_kind(atomic_kind_set(ikind), natom=natom)
            nparticles = nparticles + MAX(natom, 0)
         END DO

         ALLOCATE (efunc(nparticles))
         ALLOCATE (dfunc(3, nparticles), r(3, nparticles))

         nparticles = 0
         DO ikind = 1, SIZE(atomic_kind_set)
            CALL get_atomic_kind(atomic_kind_set(ikind), atom_list=list, natom=natom)

            DO iatom = 1, natom
               atom_a = list(iatom)
               nparticles = nparticles + 1
               !pbc returns r(i) in range [-cell%hmat(i,i)/2, cell%hmat(i,i)/2]
               !for periodic dimensions (assuming the cell is orthorombic).
               !This is not consistent with the potential on grid, where r(i) is
               !in range [0, cell%hmat(i,i)]
               !Use new pbc function with switch positive_range=.TRUE.
               r(:, nparticles) = pbc(particle_set(atom_a)%r(:), cell, positive_range=.TRUE.)
            END DO
         END DO

         !if potential is on grid, interpolate the value at r,
         !otherwise evaluate the given function
         IF (pot_on_grid) THEN
            DO iatom = 1, nparticles
               CALL interpolate_external_potential(r(:, iatom), v_ee, func=efunc(iatom), &
                                                   dfunc=dfunc(:, iatom), calc_derivatives=my_force)
            END DO
         ELSE
            CALL get_external_potential(r, ext_pot_section, func=efunc, dfunc=dfunc, calc_derivatives=my_force)
         END IF

         IF (my_force) THEN
            CALL get_qs_env(qs_env=qs_env, force=force)
         END IF

         nparticles = 0
         DO ikind = 1, SIZE(atomic_kind_set)
            CALL get_atomic_kind(atomic_kind_set(ikind), natom=natom)
            CALL get_qs_kind(qs_kind_set(ikind), zeff=zeff)

            DO iatom = 1, natom
               nparticles = nparticles + 1

               ee_core_ener = ee_core_ener + zeff*efunc(nparticles)
               IF (my_force) THEN
                  force(ikind)%eev(1:3, iatom) = dfunc(1:3, nparticles)*zeff
               END IF
            END DO
         END DO
         energy%ee_core = ee_core_ener

         DEALLOCATE (dfunc, r)
         DEALLOCATE (efunc)
      END IF
      CALL timestop(handle)
   END SUBROUTINE external_c_potential

! **************************************************************************************************
!> \brief  Low level function for computing the potential and the derivatives
!> \param r                position in realspace for each grid-point
!> \param ext_pot_section ...
!> \param func             external potential at r
!> \param dfunc            derivative of the external potential at r
!> \param calc_derivatives Whether to calculate dfunc
!> \date   12.2009
!> \par History
!>      12.2009            created [tlaino]
!>      11.2014            reading external cube file added [Juha Ritala & Matt Watkins]
!> \author Teodoro Laino [tlaino]
! **************************************************************************************************
   SUBROUTINE get_external_potential(r, ext_pot_section, func, dfunc, calc_derivatives)
      REAL(KIND=dp), DIMENSION(:, :), INTENT(IN)         :: r
      TYPE(section_vals_type), POINTER                   :: ext_pot_section
      REAL(KIND=dp), DIMENSION(:), INTENT(OUT), OPTIONAL :: func
      REAL(KIND=dp), DIMENSION(:, :), INTENT(OUT), &
         OPTIONAL                                        :: dfunc
      LOGICAL, INTENT(IN), OPTIONAL                      :: calc_derivatives

      CHARACTER(len=*), PARAMETER :: routineN = 'get_external_potential'

      CHARACTER(LEN=default_path_length)                 :: coupling_function
      CHARACTER(LEN=default_string_length)               :: def_error, this_error
      CHARACTER(LEN=default_string_length), &
         DIMENSION(:), POINTER                           :: my_par
      INTEGER                                            :: handle, j
      INTEGER(kind=int_8)                                :: ipoint, npoints
      LOGICAL                                            :: check, my_force
      REAL(KIND=dp)                                      :: dedf, dx, err, lerr
      REAL(KIND=dp), DIMENSION(:), POINTER               :: my_val

      CALL timeset(routineN, handle)
      NULLIFY (my_par, my_val)
      my_force = .FALSE.
      IF (PRESENT(calc_derivatives)) my_force = calc_derivatives
      check = PRESENT(dfunc) .EQV. PRESENT(calc_derivatives)
      CPASSERT(check)
      CALL section_vals_val_get(ext_pot_section, "DX", r_val=dx)
      CALL section_vals_val_get(ext_pot_section, "ERROR_LIMIT", r_val=lerr)
      CALL get_generic_info(ext_pot_section, "FUNCTION", coupling_function, my_par, my_val, &
                            input_variables=(/"X", "Y", "Z"/), i_rep_sec=1)
      CALL initf(1)
      CALL parsef(1, TRIM(coupling_function), my_par)

      npoints = SIZE(r, 2, kind=int_8)

      DO ipoint = 1, npoints
         my_val(1) = r(1, ipoint)
         my_val(2) = r(2, ipoint)
         my_val(3) = r(3, ipoint)

         IF (PRESENT(func)) func(ipoint) = evalf(1, my_val)
         IF (my_force) THEN
            DO j = 1, 3
               dedf = evalfd(1, j, my_val, dx, err)
               IF (ABS(err) > lerr) THEN
                  WRITE (this_error, "(A,G12.6,A)") "(", err, ")"
                  WRITE (def_error, "(A,G12.6,A)") "(", lerr, ")"
                  CALL compress(this_error, .TRUE.)
                  CALL compress(def_error, .TRUE.)
                  CALL cp_warn(__LOCATION__, &
                               'ASSERTION (cond) failed at line '//cp_to_string(__LINE__)// &
                               ' Error '//TRIM(this_error)//' in computing numerical derivatives larger then'// &
                               TRIM(def_error)//' .')
               END IF
               dfunc(j, ipoint) = dedf
            END DO
         END IF
      END DO
      DEALLOCATE (my_par)
      DEALLOCATE (my_val)
      CALL finalizef()
      CALL timestop(handle)
   END SUBROUTINE get_external_potential

! **************************************************************************************************
!> \brief                  subroutine that interpolates the value of the external
!>                         potential at position r based on the values on the realspace grid
!> \param r                 ...
!> \param grid             external potential pw grid, vee
!> \param func             value of vee at r
!> \param dfunc            derivatives of vee at r
!> \param calc_derivatives calc dfunc
! **************************************************************************************************
   SUBROUTINE interpolate_external_potential(r, grid, func, dfunc, calc_derivatives)
      REAL(KIND=dp), DIMENSION(3), INTENT(IN)            :: r
      TYPE(pw_r3d_rs_type), POINTER                      :: grid
      REAL(KIND=dp), INTENT(OUT), OPTIONAL               :: func, dfunc(3)
      LOGICAL, INTENT(IN), OPTIONAL                      :: calc_derivatives

      CHARACTER(len=*), PARAMETER :: routineN = 'interpolate_external_potential'

      INTEGER                                            :: buffer_i, buffer_j, buffer_k, &
                                                            data_source, fd_extra_point, handle, &
                                                            i, i_pbc, ip, j, j_pbc, k, k_pbc, &
                                                            my_rank, num_pe, tag
      INTEGER, DIMENSION(3)                              :: lbounds, lbounds_local, lower_inds, &
                                                            ubounds, ubounds_local, upper_inds
      LOGICAL                                            :: check, my_force
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:)           :: bcast_buffer
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:, :, :)     :: grid_buffer
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:, :, :, :)  :: dgrid
      REAL(KIND=dp), DIMENSION(3)                        :: dr, subgrid_origin
      TYPE(mp_comm_type)                                 :: gid

      CALL timeset(routineN, handle)
      my_force = .FALSE.
      IF (PRESENT(calc_derivatives)) my_force = calc_derivatives
      check = PRESENT(dfunc) .EQV. PRESENT(calc_derivatives)
      CPASSERT(check)

      IF (my_force) THEN
         ALLOCATE (grid_buffer(0:3, 0:3, 0:3))
         ALLOCATE (bcast_buffer(0:3))
         ALLOCATE (dgrid(1:2, 1:2, 1:2, 3))
         fd_extra_point = 1
      ELSE
         ALLOCATE (grid_buffer(1:2, 1:2, 1:2))
         ALLOCATE (bcast_buffer(1:2))
         fd_extra_point = 0
      END IF

      ! The values of external potential on grid are distributed among the
      ! processes, so first we have to gather them up
      gid = grid%pw_grid%para%group
      my_rank = grid%pw_grid%para%group%mepos
      num_pe = grid%pw_grid%para%group%num_pe
      tag = 1

      dr = grid%pw_grid%dr
      lbounds = grid%pw_grid%bounds(1, :)
      ubounds = grid%pw_grid%bounds(2, :)
      lbounds_local = grid%pw_grid%bounds_local(1, :)
      ubounds_local = grid%pw_grid%bounds_local(2, :)

      ! Determine the indices of grid points that are needed
      lower_inds = lbounds + FLOOR(r/dr) - fd_extra_point
      upper_inds = lower_inds + 1 + 2*fd_extra_point

      DO i = lower_inds(1), upper_inds(1)
         ! If index is out of global bounds, assume periodic boundary conditions
         i_pbc = pbc_index(i, lbounds(1), ubounds(1))
         buffer_i = i - lower_inds(1) + 1 - fd_extra_point
         DO j = lower_inds(2), upper_inds(2)
            j_pbc = pbc_index(j, lbounds(2), ubounds(2))
            buffer_j = j - lower_inds(2) + 1 - fd_extra_point

            ! Find the process that has the data for indices i_pbc and j_pbc
            ! and store the data to bcast_buffer. Assuming that each process has full z data
            IF (grid%pw_grid%para%mode .NE. PW_MODE_LOCAL) THEN
               DO ip = 0, num_pe - 1
                  IF (grid%pw_grid%para%bo(1, 1, ip, 1) <= i_pbc - lbounds(1) + 1 .AND. &
                      grid%pw_grid%para%bo(2, 1, ip, 1) >= i_pbc - lbounds(1) + 1 .AND. &
                      grid%pw_grid%para%bo(1, 2, ip, 1) <= j_pbc - lbounds(2) + 1 .AND. &
                      grid%pw_grid%para%bo(2, 2, ip, 1) >= j_pbc - lbounds(2) + 1) THEN
                     data_source = ip
                     EXIT
                  END IF
               END DO
               IF (my_rank == data_source) THEN
                  IF (lower_inds(3) >= lbounds(3) .AND. upper_inds(3) <= ubounds(3)) THEN
                     bcast_buffer(:) = &
                        grid%array(i_pbc, j_pbc, lower_inds(3):upper_inds(3))
                  ELSE
                     DO k = lower_inds(3), upper_inds(3)
                        k_pbc = pbc_index(k, lbounds(3), ubounds(3))
                        buffer_k = k - lower_inds(3) + 1 - fd_extra_point
                        bcast_buffer(buffer_k) = &
                           grid%array(i_pbc, j_pbc, k_pbc)
                     END DO
                  END IF
               END IF
               ! data_source sends data to everyone
               CALL gid%bcast(bcast_buffer, data_source)
               grid_buffer(buffer_i, buffer_j, :) = bcast_buffer
            ELSE
               grid_buffer(buffer_i, buffer_j, :) = grid%array(i_pbc, j_pbc, lower_inds(3):upper_inds(3))
            END IF
         END DO
      END DO

      ! Now that all the processes have local external potential data around r,
      ! interpolate the value at r
      subgrid_origin = (lower_inds - lbounds + fd_extra_point)*dr
      func = trilinear_interpolation(r, grid_buffer(1:2, 1:2, 1:2), subgrid_origin, dr)

      ! If the derivative of the potential is needed, approximate the derivative at grid
      ! points using finite differences, and then interpolate the value at r
      IF (my_force) THEN
         CALL d_finite_difference(grid_buffer, dr, dgrid)
         DO i = 1, 3
            dfunc(i) = trilinear_interpolation(r, dgrid(:, :, :, i), subgrid_origin, dr)
         END DO
         DEALLOCATE (dgrid)
      END IF

      DEALLOCATE (grid_buffer)
      CALL timestop(handle)
   END SUBROUTINE interpolate_external_potential

! **************************************************************************************************
!> \brief       subroutine that uses finite differences to approximate the partial
!>              derivatives of the potential based on the given values on grid
!> \param grid  tiny bit of external potential vee
!> \param dr    step size for finite difference
!> \param dgrid derivatives of grid
! **************************************************************************************************
   PURE SUBROUTINE d_finite_difference(grid, dr, dgrid)
      REAL(KIND=dp), DIMENSION(0:, 0:, 0:), INTENT(IN)   :: grid
      REAL(KIND=dp), DIMENSION(3), INTENT(IN)            :: dr
      REAL(KIND=dp), DIMENSION(1:, 1:, 1:, :), &
         INTENT(OUT)                                     :: dgrid

      INTEGER                                            :: i, j, k

      DO i = 1, SIZE(dgrid, 1)
         DO j = 1, SIZE(dgrid, 2)
            DO k = 1, SIZE(dgrid, 3)
               dgrid(i, j, k, 1) = 0.5*(grid(i + 1, j, k) - grid(i - 1, j, k))/dr(1)
               dgrid(i, j, k, 2) = 0.5*(grid(i, j + 1, k) - grid(i, j - 1, k))/dr(2)
               dgrid(i, j, k, 3) = 0.5*(grid(i, j, k + 1) - grid(i, j, k - 1))/dr(3)
            END DO
         END DO
      END DO
   END SUBROUTINE d_finite_difference

! **************************************************************************************************
!> \brief             trilinear interpolation function that interpolates value at r based
!>                    on 2x2x2 grid points around r in subgrid
!> \param r           where to interpolate to
!> \param subgrid     part of external potential on a grid
!> \param origin      center of grid
!> \param dr          step size
!> \return interpolated value of external potential
! **************************************************************************************************
   PURE FUNCTION trilinear_interpolation(r, subgrid, origin, dr) RESULT(value_at_r)
      REAL(KIND=dp), DIMENSION(3), INTENT(IN)            :: r
      REAL(KIND=dp), DIMENSION(:, :, :), INTENT(IN)      :: subgrid
      REAL(KIND=dp), DIMENSION(3), INTENT(IN)            :: origin, dr
      REAL(KIND=dp)                                      :: value_at_r

      REAL(KIND=dp), DIMENSION(3)                        :: norm_r, norm_r_rev

      norm_r = (r - origin)/dr
      norm_r_rev = 1 - norm_r
      value_at_r = subgrid(1, 1, 1)*PRODUCT(norm_r_rev) + &
                   subgrid(2, 1, 1)*norm_r(1)*norm_r_rev(2)*norm_r_rev(3) + &
                   subgrid(1, 2, 1)*norm_r_rev(1)*norm_r(2)*norm_r_rev(3) + &
                   subgrid(1, 1, 2)*norm_r_rev(1)*norm_r_rev(2)*norm_r(3) + &
                   subgrid(1, 2, 2)*norm_r_rev(1)*norm_r(2)*norm_r(3) + &
                   subgrid(2, 1, 2)*norm_r(1)*norm_r_rev(2)*norm_r(3) + &
                   subgrid(2, 2, 1)*norm_r(1)*norm_r(2)*norm_r_rev(3) + &
                   subgrid(2, 2, 2)*PRODUCT(norm_r)
   END FUNCTION trilinear_interpolation

! **************************************************************************************************
!> \brief          get a correct value for possible out of bounds index using periodic
!>                  boundary conditions
!> \param i ...
!> \param lowbound ...
!> \param upbound ...
!> \return ...
! **************************************************************************************************
   ELEMENTAL FUNCTION pbc_index(i, lowbound, upbound)
      INTEGER, INTENT(IN)                                :: i, lowbound, upbound
      INTEGER                                            :: pbc_index

      IF (i < lowbound) THEN
         pbc_index = upbound + i - lowbound + 1
      ELSE IF (i > upbound) THEN
         pbc_index = lowbound + i - upbound - 1
      ELSE
         pbc_index = i
      END IF
   END FUNCTION pbc_index

END MODULE qs_external_potential
