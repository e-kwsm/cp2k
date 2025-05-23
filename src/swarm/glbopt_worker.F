!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Worker routines used by global optimization schemes
!> \author Ole Schuett
! **************************************************************************************************
MODULE glbopt_worker
   USE cp_subsys_types,                 ONLY: cp_subsys_get,&
                                              cp_subsys_type,&
                                              pack_subsys_particles,&
                                              unpack_subsys_particles
   USE f77_interface,                   ONLY: create_force_env,&
                                              destroy_force_env,&
                                              f_env_add_defaults,&
                                              f_env_rm_defaults,&
                                              f_env_type
   USE force_env_types,                 ONLY: force_env_get,&
                                              force_env_type
   USE geo_opt,                         ONLY: cp_geo_opt
   USE global_types,                    ONLY: global_environment_type
   USE input_section_types,             ONLY: section_type,&
                                              section_vals_get_subs_vals,&
                                              section_vals_type,&
                                              section_vals_val_get,&
                                              section_vals_val_set
   USE kinds,                           ONLY: default_string_length,&
                                              dp
   USE md_run,                          ONLY: qs_mol_dyn
   USE mdctrl_types,                    ONLY: glbopt_mdctrl_data_type,&
                                              mdctrl_type
   USE message_passing,                 ONLY: mp_para_env_type
   USE physcon,                         ONLY: angstrom,&
                                              kelvin
   USE swarm_message,                   ONLY: swarm_message_add,&
                                              swarm_message_get,&
                                              swarm_message_type
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'glbopt_worker'

   PUBLIC :: glbopt_worker_init, glbopt_worker_finalize
   PUBLIC :: glbopt_worker_execute
   PUBLIC :: glbopt_worker_type

   TYPE glbopt_worker_type
      PRIVATE
      INTEGER                                  :: id = -1
      INTEGER                                  :: iw = -1
      INTEGER                                  :: f_env_id = -1
      TYPE(f_env_type), POINTER                :: f_env => NULL()
      TYPE(force_env_type), POINTER            :: force_env => NULL()
      TYPE(cp_subsys_type), POINTER            :: subsys => NULL()
      TYPE(section_vals_type), POINTER         :: root_section => NULL()
      TYPE(global_environment_type), POINTER   :: globenv => NULL()
      INTEGER                                  :: gopt_max_iter = 0
      INTEGER                                  :: bump_steps_downwards = 0
      INTEGER                                  :: bump_steps_upwards = 0
      INTEGER                                  :: md_bumps_max = 0
      REAL(KIND=dp)                            :: fragmentation_threshold = 0.0_dp
      INTEGER                                  :: n_atoms = -1
      !REAL(KIND=dp)                            :: adaptive_timestep = 0.0
   END TYPE glbopt_worker_type

CONTAINS

! **************************************************************************************************
!> \brief Initializes worker for global optimization
!> \param worker ...
!> \param input_declaration ...
!> \param para_env ...
!> \param root_section ...
!> \param input_path ...
!> \param worker_id ...
!> \param iw ...
!> \author Ole Schuett
! **************************************************************************************************
   SUBROUTINE glbopt_worker_init(worker, input_declaration, para_env, root_section, &
                                 input_path, worker_id, iw)
      TYPE(glbopt_worker_type), INTENT(INOUT)            :: worker
      TYPE(section_type), POINTER                        :: input_declaration
      TYPE(mp_para_env_type), POINTER                    :: para_env
      TYPE(section_vals_type), POINTER                   :: root_section
      CHARACTER(LEN=*), INTENT(IN)                       :: input_path
      INTEGER, INTENT(in)                                :: worker_id, iw

      INTEGER                                            :: i
      REAL(kind=dp)                                      :: dist_in_angstrom
      TYPE(section_vals_type), POINTER                   :: glbopt_section

      worker%root_section => root_section
      worker%id = worker_id
      worker%iw = iw

      ! ======= Create f_env =======
      CALL create_force_env(worker%f_env_id, &
                            input_declaration=input_declaration, &
                            input_path=input_path, &
                            input=root_section, &
                            output_unit=worker%iw, &
                            mpi_comm=para_env)

      ! ======= More setup stuff =======
      CALL f_env_add_defaults(worker%f_env_id, worker%f_env)
      worker%force_env => worker%f_env%force_env
      CALL force_env_get(worker%force_env, globenv=worker%globenv, subsys=worker%subsys)

      ! We want different random-number-streams for each worker
      DO i = 1, worker_id
         CALL worker%globenv%gaussian_rng_stream%reset_to_next_substream()
      END DO

      CALL cp_subsys_get(worker%subsys, natom=worker%n_atoms)

      ! fetch original value from input
      CALL section_vals_val_get(root_section, "MOTION%GEO_OPT%MAX_ITER", i_val=worker%gopt_max_iter)
      glbopt_section => section_vals_get_subs_vals(root_section, "SWARM%GLOBAL_OPT")

      CALL section_vals_val_get(glbopt_section, "BUMP_STEPS_UPWARDS", i_val=worker%bump_steps_upwards)
      CALL section_vals_val_get(glbopt_section, "BUMP_STEPS_DOWNWARDS", i_val=worker%bump_steps_downwards)
      CALL section_vals_val_get(glbopt_section, "MD_BUMPS_MAX", i_val=worker%md_bumps_max)
      CALL section_vals_val_get(glbopt_section, "FRAGMENTATION_THRESHOLD", r_val=dist_in_angstrom)
      !CALL section_vals_val_get(glbopt_section,"MD_ADAPTIVE_TIMESTEP", r_val=worker%adaptive_timestep)
      worker%fragmentation_threshold = dist_in_angstrom/angstrom
   END SUBROUTINE glbopt_worker_init

! **************************************************************************************************
!> \brief Central execute routine of global optimization worker
!> \param worker ...
!> \param cmd ...
!> \param report ...
!> \author Ole Schuett
! **************************************************************************************************
   SUBROUTINE glbopt_worker_execute(worker, cmd, report)
      TYPE(glbopt_worker_type), INTENT(INOUT)            :: worker
      TYPE(swarm_message_type), INTENT(IN)               :: cmd
      TYPE(swarm_message_type), INTENT(INOUT)            :: report

      CHARACTER(len=default_string_length)               :: command

      CALL swarm_message_get(cmd, "command", command)
      IF (TRIM(command) == "md_and_gopt") THEN
         CALL run_mdgopt(worker, cmd, report)
      ELSE
         CPABORT("Worker: received unknown command")
      END IF

   END SUBROUTINE glbopt_worker_execute

! **************************************************************************************************
!> \brief Performs an escape attempt as need by e.g. Minima Hopping
!> \param worker ...
!> \param cmd ...
!> \param report ...
!> \author Ole Schuett
! **************************************************************************************************
   SUBROUTINE run_mdgopt(worker, cmd, report)
      TYPE(glbopt_worker_type), INTENT(INOUT)            :: worker
      TYPE(swarm_message_type), INTENT(IN)               :: cmd
      TYPE(swarm_message_type), INTENT(INOUT)            :: report

      INTEGER                                            :: gopt_steps, iframe, md_steps, &
                                                            n_fragments, prev_iframe
      REAL(kind=dp)                                      :: Epot, temperature
      REAL(KIND=dp), DIMENSION(:), POINTER               :: positions
      TYPE(glbopt_mdctrl_data_type), TARGET              :: mdctrl_data
      TYPE(mdctrl_type), POINTER                         :: mdctrl_p
      TYPE(mdctrl_type), TARGET                          :: mdctrl

      NULLIFY (positions)

      CALL swarm_message_get(cmd, "temperature", temperature)
      CALL swarm_message_get(cmd, "iframe", iframe)
      IF (iframe > 1) THEN
         CALL swarm_message_get(cmd, "positions", positions)
         CALL unpack_subsys_particles(worker%subsys, r=positions)
      END IF

      ! setup mdctrl callback
      ALLOCATE (mdctrl_data%epot_history(worker%bump_steps_downwards + worker%bump_steps_upwards + 1))
      mdctrl_data%epot_history = 0.0
      mdctrl_data%md_bump_counter = 0
      mdctrl_data%bump_steps_upwards = worker%bump_steps_upwards
      mdctrl_data%bump_steps_downwards = worker%bump_steps_downwards
      mdctrl_data%md_bumps_max = worker%md_bumps_max
      mdctrl_data%output_unit = worker%iw
      mdctrl%glbopt => mdctrl_data
      mdctrl_p => mdctrl

      !IF(worker%adaptive_timestep > 0.0) THEN
      !   !TODO: 300K is hard encoded
      !   boltz = 1.0 + exp( -temperature * kelvin / 150.0 )
      !   timestep = 4.0 * ( boltz - 1.0 ) / boltz / femtoseconds
      !   !timestep = 0.01_dp / femtoseconds
      !   !timestep = SQRT(MIN(0.5, 2.0/(1+exp(-300.0/(temperature*kelvin))))) / femtoseconds
      !   CALL section_vals_val_set(worker%root_section, "MOTION%MD%TIMESTEP", r_val=timestep)
      !   IF(worker%iw>0)&
      !      WRITE (worker%iw,'(A,35X,F20.3)')  ' GLBOPT| MD timestep [fs]',timestep*femtoseconds
      !ENDIF

      prev_iframe = iframe
      IF (iframe == 0) iframe = 1 ! qs_mol_dyn behaves differently for STEP_START_VAL=0
      CALL section_vals_val_set(worker%root_section, "MOTION%MD%STEP_START_VAL", i_val=iframe - 1)
      CALL section_vals_val_set(worker%root_section, "MOTION%MD%TEMPERATURE", r_val=temperature)

      IF (worker%iw > 0) THEN
         WRITE (worker%iw, '(A,33X,F20.3)') ' GLBOPT| MD temperature [K]', temperature*kelvin
         WRITE (worker%iw, '(A,29X,I10)') " GLBOPT| Starting MD at trajectory frame ", iframe
      END IF

      ! run MD
      CALL qs_mol_dyn(worker%force_env, worker%globenv, mdctrl=mdctrl_p)

      iframe = mdctrl_data%itimes + 1
      md_steps = iframe - prev_iframe
      IF (worker%iw > 0) WRITE (worker%iw, '(A,I4,A)') " GLBOPT| md ended after ", md_steps, " steps."

      ! fix fragmentation
      IF (.NOT. ASSOCIATED(positions)) ALLOCATE (positions(3*worker%n_atoms))
      CALL pack_subsys_particles(worker%subsys, r=positions)
      n_fragments = 0
      DO
         n_fragments = n_fragments + 1
         IF (fix_fragmentation(positions, worker%fragmentation_threshold)) EXIT
      END DO
      CALL unpack_subsys_particles(worker%subsys, r=positions)

      IF (n_fragments > 0 .AND. worker%iw > 0) &
         WRITE (worker%iw, '(A,13X,I10)') " GLBOPT| Ran fix_fragmentation times:", n_fragments

      ! setup geometry optimization
      IF (worker%iw > 0) WRITE (worker%iw, '(A,13X,I10)') " GLBOPT| Starting local optimisation at trajectory frame ", iframe
      CALL section_vals_val_set(worker%root_section, "MOTION%GEO_OPT%STEP_START_VAL", i_val=iframe - 1)
      CALL section_vals_val_set(worker%root_section, "MOTION%GEO_OPT%MAX_ITER", &
                                i_val=iframe + worker%gopt_max_iter)

      ! run geometry optimization
      CALL cp_geo_opt(worker%force_env, worker%globenv, rm_restart_info=.FALSE.)

      prev_iframe = iframe
      CALL section_vals_val_get(worker%root_section, "MOTION%GEO_OPT%STEP_START_VAL", i_val=iframe)
      iframe = iframe + 2 ! Compensates for different START_VAL interpretation.
      gopt_steps = iframe - prev_iframe - 1
      IF (worker%iw > 0) WRITE (worker%iw, '(A,I4,A)') " GLBOPT| gopt ended after ", gopt_steps, " steps."
      CALL force_env_get(worker%force_env, potential_energy=Epot)
      IF (worker%iw > 0) WRITE (worker%iw, '(A,25X,E20.10)') ' GLBOPT| Potential Energy [Hartree]', Epot

      ! assemble report
      CALL swarm_message_add(report, "Epot", Epot)
      CALL swarm_message_add(report, "iframe", iframe)
      CALL swarm_message_add(report, "md_steps", md_steps)
      CALL swarm_message_add(report, "gopt_steps", gopt_steps)
      CALL pack_subsys_particles(worker%subsys, r=positions)
      CALL swarm_message_add(report, "positions", positions)

      DEALLOCATE (positions)
   END SUBROUTINE run_mdgopt

! **************************************************************************************************
!> \brief Helper routine for run_mdgopt, fixes a fragmented atomic cluster.
!> \param positions ...
!> \param bondlength ...
!> \return ...
!> \author Stefan Goedecker
! **************************************************************************************************
   FUNCTION fix_fragmentation(positions, bondlength) RESULT(all_connected)
      REAL(KIND=dp), DIMENSION(:)                        :: positions
      REAL(KIND=dp)                                      :: bondlength
      LOGICAL                                            :: all_connected

      INTEGER                                            :: cluster_edge, fragment_edge, i, j, &
                                                            n_particles, stack_size
      INTEGER, ALLOCATABLE, DIMENSION(:)                 :: stack
      LOGICAL, ALLOCATABLE, DIMENSION(:)                 :: marked
      REAL(KIND=dp)                                      :: d, dr(3), min_dist, s

      n_particles = SIZE(positions)/3
      ALLOCATE (stack(n_particles), marked(n_particles))

      marked = .FALSE.; stack_size = 0

      ! First particle taken as root of flooding, mark it and push to stack
      marked(1) = .TRUE.; stack(1) = 1; stack_size = 1

      DO WHILE (stack_size > 0)
         i = stack(stack_size); stack_size = stack_size - 1 !pop
         DO j = 1, n_particles
            IF (norm(diff(positions, i, j)) < 1.25*bondlength) THEN ! they are close = they are connected
               IF (.NOT. marked(j)) THEN
                  marked(j) = .TRUE.
                  stack(stack_size + 1) = j; stack_size = stack_size + 1; !push
               END IF
            END IF
         END DO
      END DO

      all_connected = ALL(marked) !did we visit every particle?
      IF (all_connected) RETURN

      ! make sure we keep the larger chunk
      IF (COUNT(marked) < n_particles/2) marked(:) = .NOT. (marked(:))

      min_dist = HUGE(1.0)
      cluster_edge = -1
      fragment_edge = -1
      DO i = 1, n_particles
         IF (marked(i)) CYCLE
         DO j = 1, n_particles
            IF (.NOT. marked(j)) CYCLE
            d = norm(diff(positions, i, j))
            IF (d < min_dist) THEN
               min_dist = d
               cluster_edge = i
               fragment_edge = j
            END IF
         END DO
      END DO

      dr = diff(positions, cluster_edge, fragment_edge)
      s = 1.0 - bondlength/norm(dr)
      DO i = 1, n_particles
         IF (marked(i)) CYCLE
         positions(3*i - 2:3*i) = positions(3*i - 2:3*i) - s*dr
      END DO

   END FUNCTION fix_fragmentation

! **************************************************************************************************
!> \brief Helper routine for fix_fragmentation, calculates atomic distance
!> \param positions ...
!> \param i ...
!> \param j ...
!> \return ...
!> \author Ole Schuett
! **************************************************************************************************
   PURE FUNCTION diff(positions, i, j) RESULT(dr)
      REAL(KIND=dp), DIMENSION(:), INTENT(IN)            :: positions
      INTEGER, INTENT(IN)                                :: i, j
      REAL(KIND=dp), DIMENSION(3)                        :: dr

      dr = positions(3*i - 2:3*i) - positions(3*j - 2:3*j)
   END FUNCTION diff

! **************************************************************************************************
!> \brief Helper routine for fix_fragmentation, calculates vector norm
!> \param vec ...
!> \return ...
!> \author Ole Schuett
! **************************************************************************************************
   PURE FUNCTION norm(vec) RESULT(res)
      REAL(KIND=dp), DIMENSION(:), INTENT(IN)            :: vec
      REAL(KIND=dp)                                      :: res

      res = SQRT(DOT_PRODUCT(vec, vec))
   END FUNCTION norm

! **************************************************************************************************
!> \brief Finalizes worker for global optimization
!> \param worker ...
!> \author Ole Schuett
! **************************************************************************************************
   SUBROUTINE glbopt_worker_finalize(worker)
      TYPE(glbopt_worker_type), INTENT(INOUT)            :: worker

      INTEGER                                            :: ierr

      CALL f_env_rm_defaults(worker%f_env)
      CALL destroy_force_env(worker%f_env_id, ierr)
      IF (ierr /= 0) CPABORT("destroy_force_env failed")
   END SUBROUTINE glbopt_worker_finalize

END MODULE glbopt_worker
